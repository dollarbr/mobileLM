package com.dollarbr.mobilelm;

// AIDL wants ids on every method or on none, and Shizuku calls destroy() at a
// fixed transaction id, so the others are numbered explicitly.
interface IPrivilegedService {
    /** Runs argv and returns [stdout, stderr, exitCode] as strings. */
    List<String> exec(in List<String> argv, long timeoutMs) = 1;
    int callerUid() = 2;
    void destroy() = 16777114;
}
