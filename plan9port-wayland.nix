# eaburns fork works in wayland :). using this until merged
# into main repo. this file is mostly a copy-paste-modify from the original
# plan9port nixpkg.
{
    pkgs,
    lib ? pkgs.lib, 
    stdenv ? pkgs.stdenv,
    fetchFromGitHub ? pkgs.fetchFromGitHub,
    fontconfig ? pkgs.fontconfig,
    freetype ? pkgs.freetype,
    libX11 ? pkgs.xorg.libX11,
    libXext ? pkgs.xorg.libXext,
    libXt ? pkgs.xorg.libXt,
    xorgproto ? pkgs.xorg.xorgproto,
    perl ? pkgs.perl, # For building web manuals
    which ? pkgs.which,
    ed ? pkgs.ed,
    ...
}:

pkgs.stdenv.mkDerivation rec {
    pname = "plan9port-wayland";
    version = "08a4f8abe423f653c80ed5ec9c01315b58659578";

    src = fetchFromGitHub {
        owner = "eaburns";
        repo = "plan9port";
        rev = "08a4f8abe423f653c80ed5ec9c01315b58659578";
        hash = "sha256-k+HA2v2hHmKwkftPutXtNjNbMbWOcNtanTWUkCRRf+M=";
    };

    postPatch = ''
        substituteInPlace bin/9c \
          --replace 'which uniq' '${which}/bin/which uniq'

        ed -sE INSTALL <<EOF
        # get /bin:/usr/bin out of PATH
        /^PATH=[^ ]*/s,,PATH=\$PATH:\$PLAN9/bin,
        # no xcbuild nonsense
        /^if.* = Darwin/+;/^fi/-c
        ${"\t"}export NPROC=$NIX_BUILD_CORES
        .
        # remove absolute include paths from fontsrv test
        /cc -o a.out -c -I.*freetype2/;/x11.c/j
        s/(-Iinclude).*-I[^ ]*/\1/
        wq
        EOF
    '';


    nativeBuildInputs = [ ed ];
    buildInputs = with pkgs; [
        perl
        which
        fontconfig
        freetype # fontsrv uses these
        libX11
        libXext
        libXt
        xorgproto
        wayland
        wayland.dev
        libxkbcommon
    ];

    configurePhase = ''
        runHook preConfigure
        cat >LOCAL.config <<EOF
        CC9='$(command -v $CC)'
        CFLAGS='$NIX_CFLAGS_COMPILE'
        LDFLAGS='$(for f in $NIX_LDFLAGS; do echo "-Wl,$f"; done | xargs echo)'
        X11='${libXt.dev}/include'
        XDG_SESSION_TYPE=wayland
        EOF

        # make '9' available in the path so there's some way to find out $PLAN9
        cat >LOCAL.INSTALL <<EOF
        #!$out/plan9/bin/rc
        mkdir $out/bin
        ln -s $out/plan9/bin/9 $out/bin/
        EOF
        chmod +x LOCAL.INSTALL

        # now, not in fixupPhase, so ./INSTALL works
        patchShebangs .
        runHook postConfigure
    '';


    buildPhase = ''
        runHook preBuild
        PLAN9_TARGET=$out/plan9 ./INSTALL -b
        runHook postBuild
    '';

    installPhase = ''
        runHook preInstall
        mkdir $out
        cp -r . $out/plan9
        cd $out/plan9

        ./INSTALL -c
        runHook postInstall
    '';

    dontPatchShebangs = true;

    doInstallCheck = true;
    installCheckPhase = ''
        $out/bin/9 rc -c 'echo rc is working.'

        # 9l can find and use its libs
        cd $TMP
        cat >test.c <<EOF
        #include <u.h>
        #include <libc.h>
        #include <thread.h>
        void
        threadmain(int argc, char **argv)
        {
            threadexitsall(nil);
        }
        EOF
        $out/bin/9 9c -o test.o test.c
        $out/bin/9 9l -o test test.o
        ./test
    '';
}
