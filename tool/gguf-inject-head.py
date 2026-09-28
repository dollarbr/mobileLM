#!/usr/bin/env python3
"""
Injeta a camada `classifier` de um classificador BERT num GGUF, como
`cls.output.weight` / `cls.output.bias`.

## Por que isto existe

Um reranker em GGUF não devolve um logit, e a falha não parece falha.

`modeling_bert.py` de um classificador BERT faz duas camadas com um `tanh` no
meio:

    pooled = tanh(pooler.dense(hidden[:, 0]))     # 384 -> 384
    logits = classifier(pooled)                   # 384 -> 1

A conversão HF→GGUF da arch `bert` guarda o `classifier` e **descarta o
`pooler.dense`**, e o llama.cpp aplica `tanh` *depois* da cabeça em vez de
antes. O que sobra é `tanh(classifier(h[0]))`: um float em (-1, 1) que
ordena documentos plausivelmente e não é score nenhum. Medido no Edge 60 com
`jina-reranker-v1-tiny-en`: **40+ leituras nunca saíram de (-1, 1)** — nem para
um documento idêntico à query, que é o par mais confiante que existe — e o
`sigmoid` do intervalo ficou entre 0,496 e 0,561, onde um reranker calibrado
quer 0,005 a 0,995. O NDCG@10 era 0,9981. A ordem estava certa e o número não
significava nada.

Pior: o `cls_out` do llama.cpp é aplicado só se o loader o preencher, e só
`bert`, `modern-bert`, `neo-bert` e `qwen3` o pedem. `jina-bert-v2`,
`jina-bert-v3`, `nomic-bert` e `eurobert` não — lá o ramo `if (cls_out)` de
`llama-graph.cpp:3753` é inalcançável, e injetar o tensor só faz o load
falhar com `wrong number of tensors`.

Então isto só serve onde `cls_out` é pedido: `bert`, `modern-bert`, `neo-bert`.
E onde o pooler também foi descartado, injetar a cabeça não basta — o
`cls` existente precisaria ser o `pooler.dense`, e isso muda o sentido do tensor
para a arch inteira. `gte-reranker-modernbert-base` é o caso que funciona sem
nada disso: `modern-bert`, com `cls.weight` 768×768, `cls.output.weight` [768],
`cls.output.bias` [1] e `cls.norm.weight`, tudo no lugar.

## Sem perda

Reescreve só o cabeçalho e anexa os bytes novos no fim. Nenhum byte dos tensores
existentes é tocado, então os blocos Q8_0 continuam idênticos — e o resultado é
verificado ao final, porque o `gguf-py` **não** valida o layout que o
`gguf.cpp` exige (veja `verify`).

## Uso

    python3 tool/gguf-inject-head.py entrada.gguf saida.gguf model.safetensors [prefixo]

O prefixo é o de `<prefixo>embedding_length` no GGUF (`bert.`, `modern-bert.`,
…), e é opcional. Não há prefixo para o safetensors: lá os tensores se chamam
`classifier.weight` e `classifier.bias`.
"""

import json
import struct
import sys

GGUF_MAGIC = b"GGUF"
ALIGN_DEFAULT = 32

# metadados: tipo -> (formato, bytes por elemento)
META_FMT = {
    0: ("<B", 1), 1: ("<b", 1), 2: ("<H", 2), 3: ("<h", 2),
    4: ("<I", 4), 5: ("<i", 4), 6: ("<f", 4), 7: ("<?", 1),
    10: ("<Q", 8), 11: ("<q", 8), 12: ("<d", 8),
}
ARRAY_ELEM = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}
F32 = 0  # GGMLType.F32


def align_up(n, a):
    return (n + a - 1) // a * a


def read_str(buf, pos):
    n, = struct.unpack_from("<Q", buf, pos)
    pos += 8
    return buf[pos:pos + n], pos + n


def read_str_array(buf, pos):
    et, = struct.unpack_from("<I", buf, pos)
    pos += 4
    count, = struct.unpack_from("<Q", buf, pos)
    pos += 8
    if et == 8:
        out = []
        for _ in range(count):
            s, pos = read_str(buf, pos)
            out.append(s)
        return out, pos
    # Qualquer outro array é pulado pelo tamanho: só a posição interessa, porque
    # a seção de metadados é reescrita a partir dos bytes crus. Um GGUF de
    # 61.056 tokens traz arrays de string enormes, e um array de bool (tipo 7) é
    # 1 byte por elemento — errar a conta aqui desalinha o arquivo inteiro sem
    # erro nenhum.
    pos += count * ARRAY_ELEM[et]
    return f"<{count} elementos tipo {et}>", pos


def parse_header(data):
    """Devolve (version, kvs, tensor_infos, data_start). Não copia nada."""
    if data[:4] != GGUF_MAGIC:
        raise SystemExit("não é um GGUF")
    version, = struct.unpack_from("<I", data, 4)
    n_tensors, = struct.unpack_from("<Q", data, 8)
    n_kv, = struct.unpack_from("<Q", data, 16)
    pos = 24
    kvs = []
    for _ in range(n_kv):
        # Os bytes crus de cada entrada são guardados porque a seção de
        # metadados é reescrita verbatim. Reconstruí-la a partir dos valores
        # exigiria serializar de volta arrays de string de 61.056 itens, bools e
        # ints, e um erro de tipo ali desloca todo o resto do arquivo sem erro
        # nenhum. Guardar o bruto e reescrever é o jeito que não pode falhar.
        start = pos
        key, pos = read_str(data, pos)
        vtype, = struct.unpack_from("<I", data, pos)
        pos += 4
        if vtype == 8:
            val, pos = read_str(data, pos)
        elif vtype == 9:
            val, pos = read_str_array(data, pos)
        elif vtype in META_FMT:
            fmt, size = META_FMT[vtype]
            val = struct.unpack_from(fmt, data, pos)[0]
            pos += size
        else:
            raise SystemExit(f"tipo de metadado {vtype} não suportado")
        kvs.append((key, vtype, val, data[start:pos]))

    infos = []
    for _ in range(n_tensors):
        name, pos = read_str(data, pos)
        n_dims, = struct.unpack_from("<I", data, pos)
        pos += 4
        dims = struct.unpack_from("<%dQ" % n_dims, data, pos)
        pos += 8 * n_dims
        ttype, = struct.unpack_from("<I", data, pos)
        pos += 4
        offset, = struct.unpack_from("<Q", data, pos)
        pos += 8
        infos.append((name, n_dims, dims, ttype, offset))

    return version, kvs, infos, align_up(pos, ALIGN_DEFAULT)


def kv_get(kvs, key, default=None):
    for k, _t, v, _raw in kvs:
        if k == key:
            return v
    return default


def bf16_to_f32(raw):
    """bf16 -> f32. Os 16 bits altos viram os 32, sinal e expoente preservados."""
    out = bytearray()
    for i in range(0, len(raw), 2):
        v, = struct.unpack_from("<H", raw, i)
        out += struct.pack("<I", v << 16)
    return bytes(out)


def safetensors_tensor(path, name):
    # safetensors é: 8 bytes de u64 com o tamanho do header, o header JSON, e os
    # dados. Não há um segundo u64 entre o header e os dados — somar 8 aqui lê o
    # tensor 8 bytes atrasado e devolve 760 dos 768 bytes de `classifier.weight`,
    # o que produz uma cabeça com 380 elementos em vez de 384 e números que
    # parecem normais.
    with open(path, "rb") as f:
        n, = struct.unpack("<Q", f.read(8))
        hdr = json.loads(f.read(n))
        meta = hdr[name]
        nel = 1
        for d in meta["shape"]:
            nel *= d
        want = nel * (2 if meta["dtype"] == "BF16" else 4)
        f.seek(8 + n + meta["data_offsets"][0])
        raw = f.read(meta["data_offsets"][1] - meta["data_offsets"][0])
    if len(raw) != want:
        raise SystemExit(
            f"{name}: li {len(raw)} bytes, o shape {meta['shape']} "
            f"({meta['dtype']}) pede {want}")
    return raw, meta["shape"], meta["dtype"]


def head_from_safetensors(path):
    """(weight, bias) em F32, mais (n_cls, n_embd)."""
    w_raw, w_shape, w_dt = safetensors_tensor(path, "classifier.weight")
    b_raw, b_shape, b_dt = safetensors_tensor(path, "classifier.bias")
    if len(w_shape) != 2 or len(b_shape) != 1:
        raise SystemExit(f"shape inesperado: weight {w_shape}, bias {b_shape}")
    if w_shape[0] != b_shape[0]:
        raise SystemExit(f"weight {w_shape} e bias {b_shape} discordam no número de saídas")
    if w_dt != "BF16" or b_dt != "BF16":
        raise SystemExit(f"dtype {w_dt}/{b_dt} != BF16 — este script só converte BF16")
    print(f"  classifier.weight {w_shape} {w_dt} · classifier.bias {b_shape} {b_dt}")
    return bf16_to_f32(w_raw), bf16_to_f32(b_raw), w_shape[0], w_shape[1]


def verify(path, sizes, n_data, expect_tensors):
    """Reproduz a regra do `gguf.cpp:787`: todo offset tem de ser igual à soma
    acumulada de GGML_PAD(ggml_nbytes, alignment).

    O `gguf-py` aceita um arquivo com offsets deslocados e calcula `t_embd` com
    `reshape` em memória — ele não percebe. O loader C++ recusa, e a recusa só
    aparece no aparelho, minutos depois, como
    `tensor 'X' has offset 128, expected 0`. Verificar aqui custa microssegundos.
    """
    with open(path, "rb") as f:
        data = f.read()
    _v, _kv, infos, data_start = parse_header(data)
    if len(infos) != expect_tensors:
        raise SystemExit(f"{len(infos)} tensores, esperava {expect_tensors}")
    if data_start != n_data:
        raise SystemExit(f"n_data {data_start} != {n_data}")
    esperado, erros = 0, []
    for (name, _nd, _dims, _tt, off), want in zip(infos, sizes):
        if off != esperado:
            erros.append((name, off, esperado))
        esperado += align_up(want, ALIGN_DEFAULT)
    if erros:
        for name, got, exp in erros[:5]:
            print(f"    {name}: offset {got}, esperado {exp}")
        raise SystemExit(f"{len(erros)} tensores fora de posição")
    if n_data + esperado != len(data):
        raise SystemExit(
            f"n_data + dados alinhados = {n_data + esperado}, arquivo tem {len(data)}")
    print(f"  verify: {len(infos)} offsets densos, seção de dados fecha em "
          f"{n_data + esperado} bytes")


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__.split("## Uso")[1].strip())
    src, dst, st_path = sys.argv[1], sys.argv[2], sys.argv[3]
    prefix = sys.argv[4] if len(sys.argv) > 4 else ""

    with open(src, "rb") as f:
        data = f.read()
    version, kvs, infos, data_start = parse_header(data)
    align = kv_get(kvs, b"general.alignment", ALIGN_DEFAULT)
    if align != ALIGN_DEFAULT:
        raise SystemExit(
            f"general.alignment = {align}, esperava {ALIGN_DEFAULT}: os offsets "
            f"seriam inválidos")

    w_f32, b_f32, n_cls, n_embd = head_from_safetensors(st_path)
    gguf_embd = kv_get(kvs, f"{prefix}embedding_length".encode())
    if gguf_embd != n_embd:
        raise SystemExit(
            f"o GGUF diz {prefix or '<arch>'}embedding_length = {gguf_embd} e o "
            f"classifier espera {n_embd}; este não é o mesmo modelo")
    print(f"  n_embd = {n_embd} (confere com o GGUF), n_cls_out = {n_cls}")
    print(f"  {len(infos)} tensores existentes, dados em [{data_start}, {len(data)})")

    # Duas entradas com o mesmo nome num GGUF não é ambíguo, é um arquivo que o
    # loader vai ler de um jeito e o gguf-py de outro. E o caso é fácil de
    # chegar: `gte-reranker-modernbert-base` já vem com a cabeça, e injetar por
    # cima criaria um segundo `cls.output.weight`.
    ja_existe = {name for name, *_rest in infos}
    for nome in (b"cls.output.weight", b"cls.output.bias"):
        if nome in ja_existe:
            raise SystemExit(
                f"{nome.decode()} já está no GGUF; este arquivo já tem cabeça de "
                f"classificação e não precisa de injeção")

    # O que o llama.cpp cria para cls_out (llama-graph.cpp:3753 e
    # llama-model.cpp:2766): ne = [n_embd, n_cls_out], F32. `ne` é o que o
    # mul_mat usa, e [384, 1] em ggml tem os mesmos 384 floats de [1, 384] em
    # PyTorch — a mesma linha, na mesma ordem de memória.
    tail_spec = [
        (b"cls.output.weight", 2, (n_embd, n_cls), F32, w_f32),
        (b"cls.output.bias", 1, (n_cls,), F32, b_f32),
    ]

    def build_header(shift=0, tail=()):
        h = bytearray()
        h += GGUF_MAGIC
        h += struct.pack("<I", version)
        h += struct.pack("<Q", len(infos) + len(tail))
        h += struct.pack("<Q", len(kvs))
        for _k, _t, _v, raw in kvs:
            h += raw
        for name, n_dims, dims, ttype, off in infos:
            h += struct.pack("<Q", len(name)) + name
            h += struct.pack("<I", n_dims)
            for d in dims:
                h += struct.pack("<Q", d)
            h += struct.pack("<I", ttype)
            h += struct.pack("<Q", off + shift)
        for name, n_dims, dims, ttype, off in tail:
            h += struct.pack("<Q", len(name)) + name
            h += struct.pack("<I", n_dims)
            for d in dims:
                h += struct.pack("<Q", d)
            h += struct.pack("<I", ttype)
            h += struct.pack("<Q", off)
        return h

    # Só a forma, para medir o header. O quinto campo de `tail_spec` é o blob,
    # não um offset — os offsets são calculados abaixo, quando `new_start` já
    # existe, e é circular depender disso para medir o tamanho do header.
    tail_shape = [(name, n_dims, dims, ttype, 0) for name, n_dims, dims, ttype, _b in tail_spec]

    # Dois tensor_infos novos fazem o header crescer, e `n_data` é o fim
    # alinhado dele — então os dados se movem com ele e nenhum offset precisa
    # mudar. Somar um `shift` aos 70 offsets velhos, além disso, desloca o
    # conteúdo duas vezes e produz exatamente o erro que o aparelho acusou.
    new_start = align_up(len(build_header(tail=tail_shape)), align)
    if new_start < data_start:
        raise SystemExit(f"header encolheu: {new_start} < {data_start}")
    print(f"  n_data: {data_start} -> {new_start} (+{new_start - data_start}, "
          f"é o próprio header que cresceu)")

    # Offsets relativos a `new_start`. O blob antigo tem `len(data) - data_start`
    # bytes e, em número absoluto, continua no mesmo lugar: o crescimento do
    # header e o offset do blob se cancelam.
    end = align_up(len(data) - data_start, align)
    tail, blobs, sizes_new = [], [], []
    for name, n_dims, dims, ttype, blob in tail_spec:
        nb = 4
        for d in dims:
            nb *= d
        if len(blob) != nb:
            raise SystemExit(f"{name.decode()}: blob tem {len(blob)} B, dims pedem {nb}")
        tail.append((name, n_dims, dims, ttype, end))
        blobs.append((end, nb, blob))
        sizes_new.append(nb)
        # O offset seguinte é o FIM ALINHADO deste, não o fim cru: o gguf.cpp
        # acumula GGML_PAD(ggml_nbytes, alignment), e os 16 bytes entre um tensor
        # de 1520 e o seguinte têm de existir no arquivo. Calcular o offset com
        # padding e escrever os dados colados põe o segundo tensor além do fim.
        end += align_up(nb, align)
    print(f"  offsets novos: {[b[0] for b in blobs]}  ·  dados em {end} bytes")

    out = bytearray(build_header(tail=tail))
    out += b"\x00" * (align_up(len(out), align) - len(out))
    if len(out) != new_start:
        raise SystemExit(f"header mede {len(out)}, esperava {new_start}")
    out += data[data_start:]
    for off, nb, blob in blobs:
        gap = off - (len(out) - new_start)
        if gap < 0:
            raise SystemExit(f"offset {off} atrás da posição {len(out) - new_start}")
        out += b"\x00" * gap
        out += blob
    # O GGML_PAD do último tensor também tem de estar no arquivo: `end` já o
    # conta. O `gguf.cpp` só compara offsets, então ler os 4 floats do bias
    # funciona sem isto — mas o formato implica que a seção de dados termine no
    # tamanho alinhado, e um arquivo 28 bytes curto é o tipo de coisa que um
    # validador mais rigoroso recusa depois.
    out += b"\x00" * (align_up(len(out) - new_start, align) - (len(out) - new_start))
    if len(out) - new_start != end:
        raise SystemExit(f"dados escritos {len(out) - new_start}, layout diz {end}")

    with open(dst, "wb") as f:
        f.write(out)
    print(f"\n  escrito: {dst}  ({len(out)} bytes, era {len(data)}, "
          f"delta {len(out) - len(data)})")

    # Os tamanhos dos tensores antigos vêm dos offsets do ORIGINAL, que o
    # llama.cpp já aceitou como densos: dispensa qualquer tabela de tamanhos por
    # tipo, que é o tipo de coisa que se erra em silêncio.
    sizes_old = [
        (infos[i + 1][4] - infos[i][4]) if i + 1 < len(infos)
        else (len(data) - data_start - infos[i][4])
        for i in range(len(infos))
    ]
    verify(dst, sizes_old + sizes_new, new_start, len(infos) + len(tail_spec))

    import math
    w = [struct.unpack_from("<f", w_f32, 4 * i)[0] for i in range(n_embd)]
    l1 = sum(abs(x) for x in w)
    b0 = struct.unpack_from("<f", b_f32, 0)[0]
    print(f"  ||W||1 = {l1:.4f}, bias = {b0:+.5f}  ->  |logit| <= {l1 + abs(b0):.4f}, "
          f"sigmoid {1 / (1 + math.exp(-(l1 + abs(b0)))):.4f}")


if __name__ == "__main__":
    main()
