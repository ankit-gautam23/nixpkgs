{ lib
, stdenv
, buildPythonPackage
, pythonOlder
, pythonAtLeast
, fetchFromGitHub
, fetchpatch
, substituteAll
, gdb
, django
, flask
, gevent
, psutil
, pytest-timeout
, pytest-xdist
, pytestCheckHook
, requests
, llvmPackages
}:

buildPythonPackage rec {
  pname = "debugpy";
  version = "1.6.6";
  format = "setuptools";

  # Currently doesn't support 3.11:
  # https://github.com/microsoft/debugpy/issues/1107
  disabled = pythonOlder "3.7" || pythonAtLeast "3.11";

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "debugpy";
    rev = "refs/tags/v${version}";
    hash = "sha256-jEhvpPO3QeKjPiOMxg2xOWitWtZ6UCWyM1WvnbrKnFI=";
  };

  patches = [
    # Use nixpkgs version instead of versioneer
    (substituteAll {
      src = ./hardcode-version.patch;
      inherit version;
    })

    # https://github.com/microsoft/debugpy/issues/1230
    (fetchpatch {
      url = "https://patch-diff.githubusercontent.com/raw/microsoft/debugpy/pull/1232.patch";
      sha256 = "sha256-m5p+xYiJ4w4GcaFIaPmlnErp/7WLwcvJmaCqa2SeSxU=";
    })

    # Fix importing debugpy in:
    # - test_nodebug[module-launch(externalTerminal)]
    # - test_nodebug[module-launch(integratedTerminal)]
    #
    # NOTE: The import failures seen in these tests without the patch
    # will be seen if a user "installs" debugpy by adding it to PYTHONPATH.
    # To avoid this issue, debugpy should be installed using python.withPackages:
    # python.withPackages (ps: with ps; [ debugpy ])
    ./fix-test-pythonpath.patch
  ] ++ lib.optionals stdenv.isLinux [
    # Hard code GDB path (used to attach to process)
    (substituteAll {
      src = ./hardcode-gdb.patch;
      inherit gdb;
    })
  ] ++ lib.optionals stdenv.isDarwin [
    # Hard code LLDB path (used to attach to process)
    (substituteAll {
      src = ./hardcode-lldb.patch;
      inherit (llvmPackages) lldb;
    })
  ];

  # Remove pre-compiled "attach" libraries and recompile for host platform
  # Compile flags taken from linux_and_mac/compile_linux.sh & linux_and_mac/compile_mac.sh
  preBuild = ''(
    set -x
    cd src/debugpy/_vendored/pydevd/pydevd_attach_to_process
    rm *.so *.dylib *.dll *.exe *.pdb
    ${stdenv.cc}/bin/c++ linux_and_mac/attach.cpp -Ilinux_and_mac -fPIC -nostartfiles ${{
      "x86_64-linux"   = "-shared -o attach_linux_amd64.so";
      "i686-linux"     = "-shared -o attach_linux_x86.so";
      "aarch64-linux"  = "-shared -o attach_linux_arm64.so";
      "x86_64-darwin"  = "-std=c++11 -lc -D_REENTRANT -dynamiclib -o attach_x86_64.dylib";
      "i686-darwin"    = "-std=c++11 -lc -D_REENTRANT -dynamiclib -o attach_x86.dylib";
      "aarch64-darwin" = "-std=c++11 -lc -D_REENTRANT -dynamiclib -o attach_arm64.dylib";
    }.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}")}
  )'';

  nativeCheckInputs = [
    django
    flask
    gevent
    psutil
    pytest-timeout
    pytest-xdist
    pytestCheckHook
    requests
  ];

  preCheck = lib.optionalString (stdenv.isDarwin && stdenv.isAarch64) ''
    # https://github.com/python/cpython/issues/74570#issuecomment-1093748531
    export no_proxy='*';
  '';

  postCheck = lib.optionalString (stdenv.isDarwin && stdenv.isAarch64) ''
    unset no_proxy
  '';

  # Override default arguments in pytest.ini
  pytestFlagsArray = [
    "--timeout=0"
  ];
  # Fixes hanging tests on Darwin
  __darwinAllowLocalNetworking = true;

  disabledTests = [
    # https://github.com/microsoft/debugpy/issues/1241
    "test_flask_breakpoint_multiproc"
  ];

  pythonImportsCheck = [
    "debugpy"
  ];

  meta = with lib; {
    description = "An implementation of the Debug Adapter Protocol for Python";
    homepage = "https://github.com/microsoft/debugpy";
    changelog = "https://github.com/microsoft/debugpy/releases/tag/v${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ kira-bruneau ];
    platforms = [ "x86_64-linux" "i686-linux" "aarch64-linux" "x86_64-darwin" "i686-darwin" "aarch64-darwin" ];
  };
}
