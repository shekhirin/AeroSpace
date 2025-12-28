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

      # Use flake source - artifacts must be committed to the repo
      # Run: nix develop -c ./build-release.sh
      # Then commit: git add -f .release .man .shell-completion && git commit
      releaseDir = "${self}/.release";
      manDir = "${self}/.man";
      shellCompletionDir = "${self}/.shell-completion";

      # Build dependencies
      buildDeps = with pkgs; [
        ruby
        fish
        jdk21
        python3
        bashInteractive  # needed for `complete` builtin in shell-completion check
      ];
    in
    {
      # Development shell with all build dependencies
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = buildDeps;

        shellHook = ''
          export JAVA_HOME=${pkgs.jdk21.home}
        '';
      };

      packages.${system} = {
        default = self.packages.${system}.aerospace;

        # Package that installs from .release directory
        # Artifacts must be committed to the repo first:
        #   1. nix develop -c ./build-release.sh
        #   2. git add -f .release .man .shell-completion
        #   3. git commit -m "Build artifacts"
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
