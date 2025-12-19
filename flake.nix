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
      appName = "AeroSpace.app";
    in
    {
      packages.${system} = {
        default = self.packages.${system}.aerospace;

        aerospace = pkgs.stdenv.mkDerivation {
          pname = "aerospace";
          inherit version;

          # Use pre-built release from the .release directory
          # Build with: ./build-release.sh --codesign-identity "aerospace-codesign-certificate"
          src = ./.release;

          nativeBuildInputs = [ pkgs.installShellFiles ];

          installPhase = ''
            runHook preInstall

            # Find the versioned directory or use current structure
            if [ -d "AeroSpace-v${version}" ]; then
              srcDir="AeroSpace-v${version}"
            else
              srcDir="."
            fi

            mkdir -p $out/Applications
            cp -r "$srcDir/${appName}" $out/Applications/ 2>/dev/null || cp -r ${appName} $out/Applications/

            mkdir -p $out/bin
            cp "$srcDir/bin/aerospace" $out/bin/ 2>/dev/null || cp bin/aerospace $out/bin/ 2>/dev/null || cp aerospace $out/bin/

            runHook postInstall
          '';

          postInstall = ''
            if [ -d "AeroSpace-v${version}/manpage" ]; then
              installManPage AeroSpace-v${version}/manpage/*
            elif [ -d "manpage" ]; then
              installManPage manpage/*
            fi

            if [ -d "AeroSpace-v${version}/shell-completion" ]; then
              shellDir="AeroSpace-v${version}/shell-completion"
            elif [ -d "shell-completion" ]; then
              shellDir="shell-completion"
            else
              shellDir=""
            fi

            if [ -n "$shellDir" ]; then
              installShellCompletion --bash "$shellDir/bash/aerospace" 2>/dev/null || true
              installShellCompletion --fish "$shellDir/fish/aerospace.fish" 2>/dev/null || true
              installShellCompletion --zsh "$shellDir/zsh/_aerospace" 2>/dev/null || true
            fi
          '';

          meta = {
            description = "i3-like tiling window manager for macOS (alexey/tabs branch)";
            homepage = "https://github.com/shekhirin/AeroSpace";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.darwin;
            mainProgram = "aerospace";
          };
        };
      };
    };
}
