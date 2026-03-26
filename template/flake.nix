{
  description = "My Basecamp module — development environment and packaging";

  inputs = {
    # Follow logos-cpp-sdk for Qt compatibility (critical — version mismatch breaks builds)
    nixpkgs.follows = "logos-cpp-sdk/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos = {
      url = "github:logos-co/logos-liblogos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, logos-cpp-sdk, logos-liblogos }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosHeaders = logos-liblogos.packages.${system}.default;

      in {
        # --- Development shell ---
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.qt6.qtbase
            pkgs.libsodium        # Remove if not needed
          ];

          shellHook = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_HEADERS="${logosHeaders}/include"

            echo "Basecamp module development environment"
            echo "  Logos SDK: $LOGOS_CPP_SDK_ROOT"
            echo "  Logos Headers: $LOGOS_LIBLOGOS_HEADERS"
            echo ""
            echo "Build commands:"
            echo "  cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug"
            echo "  cmake --build build"
            echo "  cmake --install build --prefix ~/.local"
          '';
        };

        packages = {
          # Core module for LGX bundling: lib/mymodule_plugin.so + lib/manifest.json
          lib = pkgs.stdenv.mkDerivation {
            pname = "mymodule-core";
            version = "1.0.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config ];
            buildInputs = [ pkgs.qt6.qtbase pkgs.libsodium ];
            cmakeFlags = [ "-GNinja" "-DCMAKE_BUILD_TYPE=Release" ];
            dontWrapQtApps = true;
            preConfigure = ''
              export LOGOS_CPP_SDK_ROOT="${logosSdk}"
              export LOGOS_LIBLOGOS_HEADERS="${logosHeaders}/include"
            '';
            buildPhase = ''
              cmake --build . --target mymodule_plugin -j$NIX_BUILD_CORES
            '';
            installPhase = ''
              mkdir -p $out/lib
              cp core/mymodule_plugin.so $out/lib/
              cp ${./core/manifest.json} $out/lib/manifest.json
              cp ${./core/plugin_metadata.json} $out/lib/metadata.json
            '';
          };

          # UI plugin for LGX bundling: lib/Main.qml + lib/metadata.json
          ui = pkgs.stdenv.mkDerivation {
            pname = "mymodule-ui";
            version = "1.0.0";
            src = ./ui;
            dontBuild = true;
            dontConfigure = true;
            installPhase = ''
              mkdir -p $out/lib
              cp Main.qml $out/lib/
              cp metadata.json $out/lib/
            '';
          };

          default = self.packages.${system}.lib;
        };

        # LGX packaging command
        apps.package-lgx = {
          type = "app";
          program = "${pkgs.writeShellScript "package-lgx" ''
            set -euo pipefail
            OUTPUT_DIR="''${1:-.}"
            mkdir -p "$OUTPUT_DIR"
            OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

            echo "==> Building core module LGX..."
            nix bundle --bundler github:logos-co/nix-bundle-lgx#portable .#lib

            echo "==> Copying core LGX..."
            cp -L mymodule-core-lgx-1.0.0/mymodule-core.lgx "$OUTPUT_DIR/mymodule-core.lgx"

            echo "==> Building UI module LGX..."
            nix bundle --bundler github:logos-co/nix-bundle-lgx#portable .#ui

            echo "==> Copying UI LGX..."
            cp -L mymodule-ui-lgx-1.0.0/mymodule-ui.lgx "$OUTPUT_DIR/mymodule-ui.lgx"

            echo ""
            echo "LGX packages ready in $OUTPUT_DIR:"
            echo "  - mymodule-core.lgx"
            echo "  - mymodule-ui.lgx"
          ''}";
        };
      }
    );
}
