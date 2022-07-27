{
# The name of the system for which to build, eg "x86_64-linux"
  system
# The nixpkgs to use
, pkgs
# The mach-nix (flake) to use
, mach-nix
}:
# Below, wherever we talk about a Python version, we're talking about the name
# of a Python package in nixpkgs - eg "python39".
rec {
  # Construct the name of the package for a given version of Python
  # str -> str
  packageName = pythonVersion: "tahoe-capabilities-${pythonVersion}";

  # Create a Tahoe-Capabilities package using the given Python version and
  # extras.
  #
  # str -> [str] -> derivation
  packageForVersion = extras: pythonVersion:
    pkgs.callPackage ./default.nix {
      inherit extras pythonVersion;
      inherit (mach-nix.lib.${system}) buildPythonPackage;
    };

  # Create packages for all of the given Python versions.
  #
  # [str] -> [str] -> setOf derivation
  packageForVersions = extras: pythonVersions:
    let
      mkPackage = packageForVersion extras;
    in
      builtins.foldl' (accum: pyVersion: accum // {
        ${packageName pyVersion} = mkPackage pyVersion;
      }) {} pythonVersions;

  # Compute the requirements string for Tahoe-Capabilities with the given
  # extras on the given Python version.
  #
  # [str] -> str -> str
  requirementsForVersion = extras: pythonVersion: (
    packageForVersion extras pythonVersion
  ).requirements;

  # Create a Python environment derivation using the given version of Python
  # and that contains Tahoe-Capabilities requirements (including those
  # identified by the given extras).
  #
  # [str] -> str -> derivation
  devPy = extras: pythonVersion:
    mach-nix.lib.${system}.mkPython {
      python = pythonVersion;
      inherit ((packageForVersion extras pythonVersion).meta.mach-nix) providers _;
      requirements = ''
        ${requirementsForVersion extras pythonVersion}

        # These must live in the same Python environment as all of our
        # dependencies or mypy cannot resolve imports properly.
        mypy
        mypy-zope
      '';
    };

  # Create a shell derivation for a development environment for
  # Tahoe-Capabilities for the given extras and Python version.  The resulting
  # environment places the source from the checkout first in PYTHONPATH.
  #
  # [str] -> str -> derivation
  devShellForVersion = extras: pythonVersion:
    pkgs.mkShell {
      shellHook = "export PYTHONPATH=\${PWD}/src:\${PYTHONPATH}";
      buildInputs = [
        (devPy extras pythonVersion)
        # Outside of the Python environment, a couple other helpful tools.
        # They happen to be implemented in Python but we don't want or need
        # them in our Python import path.
        pkgs.black
        pkgs.python3Packages.isort
        pkgs.python3Packages.flake8
      ];
    };

  # Create development environments for all of the given Python versions.  In
  # addition to the given extras, the "test" extra is included.
  #
  # [str] -> [str] -> setOf derivation
  devShellForVersions = extras: pythonVersions:
    let
      mkPackage = devShellForVersion (extras ++ [ "test" ]);
    in
      builtins.foldl' (accum: pyVersion: accum // {
        ${packageName pyVersion} = mkPackage pyVersion;
      }) {} pythonVersions;

  # Create a derivation that runs the automated test suite for on Python
  # version.
  #
  # [str] -> str -> derivation
  checkForVersion = extras: pythonVersion:
    pkgs.callPackage ./tests.nix {
      inherit pythonVersion;
      inherit (mach-nix.lib.${system}) mkPython;
      tahoe-capabilities = packageForVersion (extras ++ [ "test" ]) pythonVersion;
    };

  # Create derivations that run the automated test suite.
  #
  # [str] -> [str] -> setOf derivation
  checksForVersions = extras: pythonVersions:
    let
      mkCheck = checkForVersion extras;
    in
      builtins.foldl' (accum: pyVersion: accum // {
        ${packageName pyVersion + "-tests"} = mkCheck pyVersion;
      }) {} pythonVersions;

  # Create a set of derivations that includes a default that points at the
  # entry for the given Python version.
  #
  # setOf derivations -> str -> setOf derivations
  withDefault = packages: pythonVersion:
    packages // { default = packages.${packageName pythonVersion}; };
}
