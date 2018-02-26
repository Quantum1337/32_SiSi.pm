# 32_SiSi.pm
Ein FHEM Modul für den quelloffenen Messenger "[Si]gnal - [Si]cherer Messenger"

# Einleitung

Das Modul liefert eine FHEM-DBus-Schnittstelle zum Kommandozeileninterface des Messengers. [signal-cli](https://github.com/AsamK/signal-cli).

Keine Windows Unterstützung !!

# Vorbereitungen

[signal-cli](https://github.com/AsamK/signal-cli) muss im [daemon modus](https://github.com/AsamK/signal-cli/wiki/DBus-service) eingerichtet werden. Es müssen die DBus Konfiguration/Services und die systemd-Services wie unter "System Bus" beschrieben angelegt werden. Wichtig hierbei ist, dass jni/unix-java.so auf dem System installiert ist (Debian: libunixsocket-java ArchLinux: libmatthew-unix-java (AUR)) und der Nutzer "signal-cli" angelegt ist.

Ob alles richtig eingerichtet wurde, kann mit

`dbus-send --system --type=method_call --print-reply --dest="org.asamk.Signal" /org/asamk/Signal org.asamk.Signal.sendMessage string:MessageText array:string: string:RECIPIENT`

überprüft werden. Dabei wird eine Nachricht mit dem Inhalt "MessageText" an die Nummer "RECIPIENT" gesendet.

Des Weiteren müssen die PERL Module Net::DBus und IO::Socket auf dem System installiert sein.

# Installation

Das Modul in /HOMEPATH/FHEM/ ablegen und entsprechende Berechtigungen setzen. Danach in FHEM mittels  `reload 32_SiSi.pm` das Modul einbinden.

Das Attribut `enable` auf `yes` setzen. Das Modul versucht nun eine Verbindung zum entsprechenden DBus Service herzustellen.

# Funktionen

Zu diesem Zeitpunkt können Nachrichten jeglicher Art empfangen werden. Gesendet werden können Nachrichten an Empfänger wahlweise mit Anhang. Das Senden von Gruppennachrichten wird noch nicht unterstützt.

Nachricht senden:

`Usage: set <NAME> sendMessage m="MESSAGE" r=RECIPIENT1,RECIPIENT2,RECIPIENTN [a="PATH1,PATH2,PATHN"]`

# Wichtig

Das Modul befindet sich noch in früher Entwicklungsphase. Fehlfunktionen daher nicht ausgeschlossen !
