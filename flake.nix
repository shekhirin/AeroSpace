{
  description = "AeroSpace - i3-like tiling window manager for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };

      version = "0.0.0-tabs";

      # Use absolute path to the AeroSpace directory (requires --impure)
      srcRoot = "/Users/shekhirin/projects/oss/AeroSpace";

      # Import local directories into the Nix store
      releaseDir = builtins.path {
        path = builtins.toPath "${srcRoot}/.release";
        name = "aerospace-release";
      };

      manDir = builtins.path {
        path = builtins.toPath "${srcRoot}/.man";
        name = "aerospace-man";
      };

      shellCompletionDir = builtins.path {
        path = builtins.toPath "${srcRoot}/.shell-completion";
        name = "aerospace-shell-completion";
      };
    in
    {
      # Development shell with all build dependencies
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          ruby
          fish
          jdk21
          python3
        ];

        shellHook = ''
          export JAVA_HOME=${pkgs.jdk21.home}
        '';
      };

      packages.${system} = {
        default = self.packages.${system}.aerospace;

        # Package that installs from .release directory
        # Usage:
        #   1. ./build-release.sh (or: nix develop -c ./build-release.sh)
        #   2. nix build .#aerospace --impure
        aerospace = pkgs.runCommand "aerospace-${version}" {
          nativeBuildInputs = [ pkgs.installShellFiles ];
          meta = {
            description = "i3-like tiling window manager for macOS (alexey/tabs branch)";
            homepage = "https://github.com/shekhirin/AeroSpace";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.darwin;
            mainProgram = "aerospace";
          };
        } ''
          mkdir -p $out/Applications
          cp -r "${releaseDir}/AeroSpace.app" $out/Applications/

          mkdir -p $out/bin
          cp "${releaseDir}/aerospace" $out/bin/

          # Install man pages
          mkdir -p $out/share/man/man1
          cp ${manDir}/*.1 $out/share/man/man1/

          # Install shell completions
          mkdir -p $out/share/bash-completion/completions
          mkdir -p $out/share/fish/vendor_completions.d
          mkdir -p $out/share/zsh/site-functions
          cp "${shellCompletionDir}/bash/aerospace" $out/share/bash-completion/completions/ 2>/dev/null || true
          cp "${shellCompletionDir}/fish/aerospace.fish" $out/share/fish/vendor_completions.d/ 2>/dev/null || true
          cp "${shellCompletionDir}/zsh/_aerospace" $out/share/zsh/site-functions/ 2>/dev/null || true
        '';
      };
    };
}
