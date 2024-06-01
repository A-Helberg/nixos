{
  description = "Andre's nixos setup";

  inputs = {

    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }: 
  let 
    inherit (self) outputs;
    system = "x86_64-linux";
    inputs = { inherit inputs; };
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
  in
  {

    nixosConfigurations = {
      HBD = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit system inputs outputs;
        };

        modules = [
          ./nixos/HBD/configuration.nix
        ];
      };
    };

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
