{
  description = "A library for working with Tahoe-LAFS capability values";
  inputs.nixpkgs = {
    url = "github:NixOS/nixpkgs";
  };
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.pypi-deps-db = {
    flake = false;
    url = "github:DavHau/pypi-deps-db";
  };
  inputs.mach-nix = {
    flake = true;
    url = "github:DavHau/mach-nix";
    inputs = {
      pypi-deps-db.follows = "pypi-deps-db";
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, mach-nix, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system: let

      lib = import ./nix/lib.nix {
        inherit system pkgs mach-nix;
      };
      inherit (lib) checksForVersions packageForVersions devShellForVersions withDefault;

      pkgs = nixpkgs.legacyPackages.${system};

      # the Python version used by the default package
      defaultPythonVersion = "python39";

      # the Python versions for which packages are available
      supportedPythonVersions = ["python37" "python38" "python39"];

    in rec {
      packages =
        let
          packages = packageForVersions [] supportedPythonVersions;
          tests = checksForVersions ["test"] supportedPythonVersions;
        in
          # Define tests alongside the packages because it's easier to pick
          # and choose which to run this way (as compared to making them all
          # "checks").
          withDefault (packages // tests) defaultPythonVersion;

      apps.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/tahoe";
      };

      devShells =
        withDefault
          (devShellForVersions ["test"] supportedPythonVersions)
          defaultPythonVersion;
    });
}
