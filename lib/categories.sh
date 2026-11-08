# One taxonomy for inspection, selection, and component operations.
pkg_category() {
    case $1 in
        DEBIAN/control) printf control ;;
        DEBIAN/preinst|DEBIAN/postinst|DEBIAN/prerm|DEBIAN/postrm|DEBIAN/config) printf lifecycle ;;
        DEBIAN|DEBIAN/*) printf metadata ;;
        lib/systemd|lib/systemd/*|usr/lib/systemd|usr/lib/systemd/*|etc/systemd|etc/systemd/*|etc/init.d|etc/init.d/*|etc/init|etc/init/*) printf service ;;
        bin|bin/*|sbin|sbin/*|usr/bin|usr/bin/*|usr/sbin|usr/sbin/*|usr/games/*|usr/local/bin/*|usr/local/sbin/*) printf executable ;;
        etc|etc/*) printf configuration ;;
        usr/share/doc|usr/share/doc/*|usr/share/man|usr/share/man/*|usr/share/info|usr/share/info/*) printf documentation ;;
        usr/share/applications|usr/share/applications/*|usr/share/icons|usr/share/icons/*|usr/share/pixmaps|usr/share/pixmaps/*|usr/share/mime|usr/share/mime/*) printf desktop ;;
        usr/share/*|usr/lib/*|usr/libexec/*|lib/*|lib64/*) printf asset ;;
        *) printf other ;;
    esac
}
pkg_type() {
    case $1 in
        package|dependency|executable|configuration|service|documentation|asset|desktop|metadata|lifecycle|other|control) printf '%s' "$1" ;;
        dep|dependencies|--dep|--deps) printf dependency ;;
        exe|executables|--executables) printf executable ;;
        config) printf configuration ;;
        doc) printf documentation ;;
        assets) printf asset ;;
        *) return 1 ;;
    esac
}
