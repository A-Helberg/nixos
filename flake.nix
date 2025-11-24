{
  description = "Andre's nixos setup";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs?ref=master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-helper.url = "github:viperML/nh";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    catppuccin.url = "github:catppuccin/nix";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, catppuccin, nix-helper, nixpkgs-bleeding, nixpkgs-stable, ... }@inputs: 
  let 
    inherit (self) outputs;
    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

    nh_overlay = final: prev: {
      nh = inputs.nix-helper.packages.${prev.system}.default;
    };

    # https://github.com/paholg/dotfiles/blob/main/flake.nix
    pkgs_overlay = final: prev: {
      #vimPlugins = prev.vimPlugins // {
      #  catppuccin = prev.vimPlugins.catppuccin.overrideAttrs (oldAttrs: {
      #    name = "catppuccin-nvim-theme";
      #  });
      #};

    };

    forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
      pkgs-stable = import nixpkgs-stable { inherit nh_overlay system;  config.allowUnfree = true; };
      pkgs = import nixpkgs { inherit nh_overlay system;  config.allowUnfree = true; };
      pkgs-bleeding = import nixpkgs-bleeding { inherit nh_overlay system;  config.allowUnfree = true; };
    });

    mkHome = system: modules:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        inherit modules;
      };

  in
  {
    nixosConfigurations = forEachSupportedSystem ({ pkgs, pkgs-stable }: {
      HBD = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };

        modules = [
          ./nixos/HBD/configuration.nix
        ];
      };
      nephelae = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };

        modules = [
          ./nixos/nephelae/configuration.nix
        ];
      };
      kraken = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs outputs;
        };

        modules = [
          ./nixos/kraken/configuration.nix
        ];
      };
    });

    darwinConfigurations = {
      phoenix = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs outputs;
        };

        modules = [
          ./nixos/phoenix/configuration.nix
          # does not work becuase grub?
          # catppuccin.nixosModules.catppuccin
          nix-homebrew.darwinModules.nix-homebrew
          {
            # Keep Homebrew basic wiring here; host-specific knobs live in the host module
            nix-homebrew = {
              enable = true;
              user = "andre"; # User owning the Homebrew prefix
              # NOTE: enableRosetta and other settings are defined in nixos/phoenix/configuration.nix
            };
          }
        ];
      };
    };

    # Provide a formatter per system so `nix fmt` works (kept simple; extend as needed)
    formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.alejandra);

    homeConfigurations = {
      "andre@demo" = mkHome "x86_64-linux" [
        ./home-manager/home.nix
        ./home-manager/linux.nix
      ];
      "andre@HBD" = mkHome "x86_64-linux" [
        ./home-manager/home.nix
        ./home-manager/linux.nix
      ];
      "andre@nephelae" = mkHome "x86_64-linux" [
        ./home-manager/home.nix
        ./home-manager/linux.nix
      ];
      "andre@kraken" = mkHome "x86_64-linux" [
        ./home-manager/home.nix
        ./home-manager/linux.nix
      ];
      "andre@phoenix" = mkHome "aarch64-darwin" [
        catppuccin.homeModules.catppuccin
        ./home-manager/home.nix
        ./home-manager/macos.nix
      ];
    };

    # Developer environments kept out of the HM profile to avoid heavy deps in the base environment
    devShells = forEachSupportedSystem ({ pkgs, pkgs-stable, pkgs-bleeding }: {
      # Lightweight default shell for general work
      default = pkgs.mkShell {
        # Keep base tools here to avoid pulling language toolchains by default
        packages = with pkgs; [ git jq ripgrep fd fzf ];
      };

      # JavaScript/TypeScript shell – isolates node/tsserver from HM profile
      # Add common JS/TS tools; keep them isolated from the global profile
      js = pkgs.mkShell {
        packages = with pkgs; [ nodejs yarn typescript-language-server typescript eslint_d prettierd ];
      };

      # Python shell – isolates numpy/openblas and friends
      # Keep scientific stack out by default; extend per-project via requirements
      python = pkgs.mkShell {
        packages = with pkgs; [ (python3.withPackages (ps: [ ps.pip ps.virtualenv ps.uv ])) ruff ];
      };

      # Rust shell – cargo/rustup kept out of global profile
      # Useful extras for faster iteration/testing
      rust = pkgs.mkShell {
        packages = with pkgs; [ rustc cargo rust-analyzer-unwrapped cargo-watch cargo-nextest ];
      };

      # OCaml shell – isolates opam/ocaml tooling
      ocaml = pkgs.mkShell {
        packages = with pkgs; [ ocaml ocamlPackages.dune ocamlPackages.utop ocamlformat opam ];
      };
    });

  };
}
