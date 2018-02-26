# 32_SiSi.pm
Ein FHEM Modul für den quelloffenen Messenger "[Si]gnal - [Si]cherer Messenger"

# Einleitung

Das Modul liefert eine FHEM-DBus-Schnittstelle zum Kommandozeileninterface des Messengers. [signal-cli](https://github.com/AsamK/signal-cli).

Keine Windows Unterstützung !!

# Vorbereitungen

[signal-cli](https://github.com/AsamK/signal-cli) muss im [daemon modus](https://github.com/AsamK/signal-cli/wiki/DBus-service) eingerichtet werden. Es müssen die DBus Konfigurationen wie beschrieben angelegt werden. Wichtig hierbei ist, dass jni/unix-java.so auf dem System installiert ist (Debian: libunixsocket-java ArchLinux: libmatthew-unix-java (AUR)) und der Nutzer "signal-cli" angelegt ist.

Ob alles richtig eingerichtet wurde, kann mit

`dbus-send --system --type=method_call --print-reply --dest="org.asamk.Signal" /org/asamk/Signal org.asamk.Signal.sendMessage string:MessageText array:string: string:RECIPIENT`

überprüft werden. Dabei wird eine Nachricht mit dem Inhalt "MessageText" an die Nummer "RECIPIENT" gesendet.

Des Weiteren müssen die PERL Module Net::DBus und IO::Socket auf dem System installiert sein.
