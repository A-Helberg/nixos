{
  description = "Andre's nixos setup";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    nh_darwin.url = "github:ToyVo/nh_darwin";
    #nh_darwin.inputs.nixpkgs.follows = "nixpkgs";
    fml.url =  "github:ToyVo/nh_darwin";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, ... }@inputs: 
  let 
    inherit (self) outputs;
    systems = ["x86_64-linux" "x86_64-darwin"];
    inputs = { inherit inputs; };
    forAllSystems = nixpkgs.lib.genAttrs systems;
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
    };

    darwinConfigurations = {
      phoenix = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs outputs ;
        };
        system = "x86_64-darwin";
        modules = [
          ./nixos/phoenix/configuration.nix

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
        extraSpecialArgs = {inherit inputs outputs;};
        # > Our main home-manager configuration file <
        modules = [./home-manager/home.nix];
      };
    };

  };
}
