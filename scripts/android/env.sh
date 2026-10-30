# Source this before building for Android: `source scripts/android/env.sh`.
#
# Resolves the SDK, NDK and JDK from the environment (or the usual install locations) and exports
# the cross-compilers the Rust crates' build scripts need (rusqlite, ring, rustypipe's QuickJS).
# Nothing here is machine-specific: every path is either inherited or discovered.
#
#   ANDROID_HOME  SDK root. Default: $ANDROID_SDK_ROOT, then ~/Android/Sdk.
#   NDK_HOME      NDK root. Default: the newest $ANDROID_HOME/ndk/<version>.
#   JAVA_HOME     A JDK 17 or 21 for Gradle/AGP. Default: left as is, else /usr/lib/jvm/java-17*.
#   ANDROID_API   API level the native code targets (= minSdk). Default: 26.

export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
if [ ! -d "$ANDROID_HOME" ]; then
  echo "env.sh: no Android SDK at $ANDROID_HOME (set ANDROID_HOME)" >&2
  return 1 2>/dev/null || exit 1
fi
if [ -z "${NDK_HOME:-}" ]; then
  NDK_HOME="$(ls -d "$ANDROID_HOME"/ndk/*/ 2>/dev/null | sort -V | tail -1)"
  NDK_HOME="${NDK_HOME%/}"
fi
export NDK_HOME
export ANDROID_NDK_HOME="$NDK_HOME"
if [ ! -d "$NDK_HOME/toolchains/llvm" ]; then
  echo "env.sh: no NDK found (install one: sdkmanager 'ndk;28.2.13676358')" >&2
  return 1 2>/dev/null || exit 1
fi
if [ -z "${JAVA_HOME:-}" ]; then
  # `find` rather than a glob: zsh aborts on a glob that matches nothing.
  for j in $(find /usr/lib/jvm -maxdepth 1 \( -name 'java-17*' -o -name 'java-21*' \
      -o -name 'temurin-17*' -o -name 'temurin-21*' \) 2>/dev/null | sort); do
    [ -x "$j/bin/java" ] && export JAVA_HOME="$j" && break
  done
fi

ANDROID_API="${ANDROID_API:-26}"
_tc="$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
for _t in aarch64-linux-android x86_64-linux-android; do
  _u="$(echo "$_t" | tr 'a-z-' 'A-Z_')"
  _l="$(echo "$_t" | tr '-' '_')"
  export "CC_${_l}=$_tc/${_t}${ANDROID_API}-clang"
  export "CXX_${_l}=$_tc/${_t}${ANDROID_API}-clang++"
  export "AR_${_l}=$_tc/llvm-ar"
  export "RANLIB_${_l}=$_tc/llvm-ranlib"
  export "CARGO_TARGET_${_u}_LINKER=$_tc/${_t}${ANDROID_API}-clang"
  # bindgen (rquickjs-sys) must parse the NDK's headers, not the build host's /usr/include.
  export "BINDGEN_EXTRA_CLANG_ARGS_${_l}=--sysroot=$_tc/../sysroot"
done
unset _tc _t _u _l
