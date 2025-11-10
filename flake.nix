{
  description = "Andre's nixos setup";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs?ref=master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-helper.url = "github:viperML/nh";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    catppuccin.url = "github:catppuccin/nix";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, catppuccin, nix-helper, nixpkgs-bleeding, ... }@inputs: 
  let 
    inherit (self) outputs;

    # https://github.com/paholg/dotfiles/blob/main/flake.nix
    pkgs_overlay = final: prev: {
      #vimPlugins = prev.vimPlugins // {
      #  catppuccin = prev.vimPlugins.catppuccin.overrideAttrs (oldAttrs: {
      #    name = "catppuccin-nvim-theme";
      #  });
      #};

    };

    nh_overlay = final: prev: {
      nh = inputs.nix-helper.packages.${prev.system}.default;
    };

    pkgs = system:
      import inputs.nixpkgs {
        inherit system;
        overlays = [
          nh_overlay
        ];
        # FIXME
        config.allowUnfree = true;
      };

    pkgs-bleeding = system:
      import inputs.nixpkgs-bleeding {
        inherit system;
        overlays = [
          nh_overlay
        ];
        # FIXME
        config.allowUnfree = true;
      };

  in
  {

    nixosConfigurations = {
      HBD = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs outputs;
        };

        modules = [
          ./nixos/HBD/configuration.nix
        ];
      };
      nephelae = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs outputs;
        };

        modules = [
          ./nixos/nephelae/configuration.nix
        ];
      };
      kraken = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs outputs;
          pkgs-bleeding = pkgs-bleeding "x86_64-linux";
        };

        modules = [
          ./nixos/kraken/configuration.nix
        ];
      };
    };

    darwinConfigurations = {
      phoenix = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs outputs ;
          system = "aarch-darwin";
        };
        system = "aarch-darwin";
        
        modules = [
          { nixpkgs.pkgs = pkgs "aarch64-darwin"; }
          ./nixos/phoenix/configuration.nix
          # does not work becuase grub?
          #catppuccin.nixosModules.catppuccin
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true; # Apple Silicon Only
              user = "andre"; # User owning the Homebrew prefix
            };
          }
        ];
      };

      "Zanes-MacBook-Air-2" = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs outputs ;
          system = "aarch-darwin";
        };
        system = "aarch-darwin";
        
        modules = [
          { nixpkgs.pkgs = pkgs "aarch64-darwin"; }
          ./nixos/zane/configuration.nix
          # does not work becuase grub?
          #catppuccin.nixosModules.catppuccin
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true; # Apple Silicon Only
              user = "andre"; # User owning the Homebrew prefix
            };
          }
        ];
      };
    };

    #darwinPackages = self.darwinConfigurations.phoenix.pkgs;

    homeConfigurations = {
      "andre@demo" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs "x86_64-linux";
	      # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
      "andre@HBD" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs "x86_64-linux";
	      # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
      "andre@nephelae" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs "x86_64-linux";
          # > Our main home-manager configuration file <
          modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
      "andre@phoenix" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs "aarch64-darwin";
        # > Our main home-manager configuration file <
        modules = [
            catppuccin.homeModules.catppuccin
            ./home-manager/home.nix
            ./home-manager/macos.nix
        ];
      };
      "andre@Zanes-MacBook-Air-2" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs "aarch64-darwin";
        # > Our main home-manager configuration file <
        modules = [
            catppuccin.homeModules.catppuccin
            ./home-manager/home.nix
            ./home-manager/macos.nix
        ];
      };
      "andre@kraken" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs "x86_64-linux";
        # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
    };

  };
}
