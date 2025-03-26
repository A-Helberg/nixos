# Usage

`nh home swith`
and
`nh os switch`
## Troubleshooting

### github rate limit
Export this with your own PAT (for sudo user)
export NIX_CONFIG="access-tokens = github.com=ghp_...."


## TODO:
* Make an automatic disk formatter using disko like [vimjoyer](https://www.youtube.com/watch?v=YPKwkWtK7l0)

#### Update a specific input
`nix flake lock --update-input nixpkgs`
