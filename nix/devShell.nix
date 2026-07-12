{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = [
    pkgs.cargo
    pkgs.rustc
    pkgs.yt-dlp
    pkgs.ffmpeg
    pkgs.redis
  ];
}