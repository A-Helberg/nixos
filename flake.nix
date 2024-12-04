{
  description = "Andre's nixos setup";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-bleeding.url = "github:nixos/nixpkgs?ref=master";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.05";

    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nh_darwin.url = "github:ToyVo/nh_darwin";
    catppuccin.url = "github:catppuccin/nix";
  };

  outputs = { self, nixpkgs, nixpkgs-stable, nixpkgs-bleeding, home-manager, nix-darwin, nix-homebrew, catppuccin, ... }@inputs: 
  let 
    inherit (self) outputs;
    systems = ["x86_64-linux" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    #forAllSystems = nixpkgs-bleeding.lib.genAttrs systems;
    #pkgs = import nixpkgs {
    #  inherit system;
    #  config = {
    #    allowUnfree = true;
    #  };
    #};
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
          pkgs-bleeding = nixpkgs-bleeding.legacyPackages.x86_64-linux;
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
        };
        system = "x86_64-darwin";
        modules = [
          ./nixos/phoenix/configuration.nix
            # does not work becuase grub?
            #catppuccin.nixosModules.catppuccin
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              # Apple Silicon Only
              # enableRosetta = true;
              # User owning the Homebrew prefix
              user = "andre";
            };
          }
        ];
      };
    };
    darwinPackages = self.darwinConfigurations.phoenix.pkgs;

    homeConfigurations = {
      "andre@HBD" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;
          pkgs-stable = nixpkgs-stable.legacyPackages.x86_64-linux;};
        # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
      "andre@nephelae" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;
          pkgs-stable = nixpkgs-stable.legacyPackages.x86_64-linux;};
        # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
      "andre@phoenix" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-darwin; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;
          pkgs-stable = nixpkgs-stable.legacyPackages.x86_64-darwin;};
        # > Our main home-manager configuration file <
        modules = [
            catppuccin.homeManagerModules.catppuccin
            ./home-manager/home.nix
            ./home-manager/macos.nix
        ];
      };
      "andre@kraken" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;
          pkgs-stable = nixpkgs-stable.legacyPackages.x86_64-linux;};
        # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix ./home-manager/linux.nix];
      };
    };

  };
}
