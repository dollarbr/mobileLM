#!/usr/bin/env bash
# Checagem de sintaxe do JNI em segundos, em vez de um ciclo de CI de 22 minutos.
#
# ## Por que existe
#
# `flutter analyze` não compila C++ nem Kotlin. O Kotlin só aparece no
# `flutter build`, e o C++ só no `buildCMakeDebug[arm64-v8a]`. Cada um desses
# erros custou um run inteiro: o `FloatArray.toDoubleArray()` levou 22 minutos
# para aparecer, e o `enum llama_pooling_type` mais 22. Este script transformou
# o segundo em oito segundos.
#
# ## O que ele cobre, e o que não
#
# **Cobre:** `jni_wrapper.cpp` contra o `llama.h` real do llama.cpp vendorizado,
# no alvo aarch64 de verdade, com os headers do NDK. É a mesma tradução que o
# CMake faz — `-fsyntax-only` não gera código, então não pega erro de link.
#
# **Não cobre:** Kotlin, o link, nem qualquer coisa em tempo de execução. O
# `kotlinc` não está instalado nesta máquina e o JDK do host não traz as
# bibliotecas Android, então o Kotlin continua sendo o que o CI descobre.
#
# ## O compilador
#
# Não é o `g++` do host: ele não tem o sysroot do Android, e misturar os headers
# do NDK com a libstdc++ do host dá `missing binary operator before token '('`
# em `__GLIBC_PREREQ` — uma parede de erros que não tem nada a ver com o seu
# código. O certo é o clang do NDK com o triple aarch64, que é o mesmo
# compilador que o build real usa.
#
# ## A armadilha do `AGENTS.md`
#
# A nota diz que nenhuma build Android funciona localmente nesta máquina aarch64
# porque as ferramentas do NDK são x86-64. Isso é verdade para *executar* o
# resultado — linkar um binário arm64 exige um linker que é executado, e um
# assembler arm64. **Compilar para arm64 é grátis**; o `clang++` é um compilador
# cruz que produz saída aarch64 a partir de um host x86-64. Por isso a nota
# precisa ser lida como "não dá para *rodar* o artefato", e não "não dá para
# *compilar*".
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

CPP_ROOT=local_plugins/llama_flutter_android/android/src/main/cpp
TARGET=jni_wrapper.cpp
INCLUDES=(
  -I "$CPP_ROOT/llama.cpp/include"
  -I "$CPP_ROOT/llama.cpp/ggml/include"
  -I "$CPP_ROOT/llama.cpp/tools/mtmd"
)

# Ache o NDK: ANDROID_NDK_HOME primeiro, depois a instalação do SDK, depois
# qualquer ndk-* em ~/Android/Sdk. Sem isso o script morre com uma mensagem
# que parece erro de sintaxe.
find_clang() {
  if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -x "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang++" ]; then
    echo "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang++"
    return 0
  fi
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" /opt/android-sdk /usr/local/lib/android/sdk; do
    [ -d "$sdk/ndk" ] || continue
    for d in "$sdk"/ndk/*/; do
      c="$d/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang++"
      [ -x "$c" ] && { echo "$c"; return 0; }
    done
  done
  return 1
}

CLANG=$(find_clang) || {
  echo "jni-syntax: nenhum clang aarch64 do NDK encontrado." >&2
  echo "  exporte ANDROID_NDK_HOME, ou instale um NDK via sdkmanager." >&2
  exit 2
}

echo "jni-syntax: $("$CLANG" --version | head -1)"
echo "jni-syntax: compilando $TARGET para aarch64-linux-android28, sem gerar código"

if "$CLANG" -std=c++17 -fsyntax-only "${INCLUDES[@]}" "$CPP_ROOT/$TARGET"; then
  echo "jni-syntax: ok"
  exit 0
fi

echo "jni-syntax: FALHOU. O próximo build do CI levaria ~22 minutos para dizer isto." >&2
exit 1
