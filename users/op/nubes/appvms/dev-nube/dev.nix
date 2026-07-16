{ pkgs, nixvim, ... }: let
  homeDirectory = "/home/user";
in
{
  imports = [ nixvim.homeModules.nixvim ];
  programs.nixvim = import ./nixvim.nix { inherit pkgs; } // {
    enable = true;
    nixpkgs.pkgs = pkgs;
  };

  home.username = "user";
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.05";
  home.packages = with pkgs; [
    xclip
    nerd-fonts.jetbrains-mono
    vim
    ruff
    uv
  ];
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    # Required for my dotfiles to properly load development stuff for nvim
    PROFILE_TYPE = "dev-qube";
  };

  # Programs
  programs.git = {
    enable = true;
    settings = {
      user.name = "op";
      user.email = "op@qixos.org";
      extraConfig = {
        init.defaultBranch = "master";
        pull.rebase = true;
      };
      alias = {
        gr = "log --oneline --graph --decorate";
        gra = "log --oneline --graph --decorate --all";
        grs = "log --graph --pretty=format:'%Cred%h%Creset - %Cblue%G?%Creset %s %C(yellow)%d %C(bold blue)<%an>'";
      };
    };
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    shortcut = "b";
    terminal = "tmux-256color";
    escapeTime = 0;
  };

  #programs.neovim = {
  #  enable = true;
  #  defaultEditor = true;
  #};
  # Symlink neovim conf to dotfiles
  #xdg.configFile."nvim".source = "${dotfiles}/.config/nvim";

  #programs.alacritty = {
  #  enable = true;
  #  settings.shell.program = "${pkgs.zsh}/bin/zsh";
  #};

  programs.bash.enable = true;
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = false;
    initContent = ''
      ns() {
        local pkgs=(''${@/#/nixpkgs#})
        nix shell "''${pkgs[@]}"
      }
    '';
    shellAliases = {
      here = "st </dev/null &>/dev/null & disown";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      git_branch.symbol = " ";
      directory.truncation_length = 3;
    };
  };
  
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    tmux.enableShellIntegration = true;
  };

  programs.fish = {
    enable = true;
    functions = {
      ns.body = ''
        set pkgs (string replace -r '^' 'nixpkgs#' -- $argv)
        nix shell $pkgs
      '';
    };
  };
}
