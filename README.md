# 32_SiSi.pm
Ein FHEM Modul für den quelloffenen Messenger "[Si]gnal - [Si]cherer Messenger"

# Einleitung

Das Modul liefert eine FHEM-DBus-Schnittstelle zum Kommandozeileninterface [signal-cli](https://github.com/AsamK/signal-cli) des Messengers [Signal](https://signal.org/). Signal ist ein sicherer, freier und quelloffener Messenger Dienst. Sowohl die [Clienten](https://github.com/signalapp) als auch der [Server](https://github.com/signalapp/Signal-Server) sind für jedermann frei einsehbar. Das Protokoll zur E2E-Verschlüsselung ist ebenfalls frei und quelloffenen.

Bisher nur Unterstützung für Linux!

# Vorbereitungen

[signal-cli](https://github.com/AsamK/signal-cli) muss im [daemon modus](https://github.com/AsamK/signal-cli/wiki/DBus-service) eingerichtet werden. Es müssen die DBus Konfiguration/Services und die systemd-Services wie unter **"System Bus"** beschrieben angelegt werden.

## Hervorhebungen

* Die Bibliothek jni/unix-java.so muss auf dem System installiert sein (Debian: libunixsocket-java ArchLinux: libmatthew-unix-java (AUR)).
* Der Nutzer "signal-cli" muss angelegt ist.
* Wenn schon eine Nummer registriert ist, liegt im Verzeichnis `~/.config/signal` ein Ordner "data", der den privaten Schlüssel der registrierten Nummer enthält. Diese muss rekursiv nach  `/var/lib/signal-cli/` kopiert werden. Danach müssen die Rechte auf den Nutzer signal-cli übertragen werden: `sudo chown -R signal-cli:signal-cli /var/lib/signal-cli/data`
* Das Modul unterstützt momentan noch **nicht** den DBus "Session Bus", deshalb ist die Einrichtung des **"System Bus"** zwingend erforderlich.

Ob alles richtig eingerichtet wurde, kann mit

`dbus-send --system --type=method_call --print-reply --dest="org.asamk.Signal" /org/asamk/Signal org.asamk.Signal.sendMessage string:MessageText array:string: string:RECIPIENT`

überprüft werden. Dabei wird eine Nachricht mit dem Inhalt "MessageText" an die Nummer "RECIPIENT" gesendet.

# Abhängigkeiten

Die Perl Module **Net::DBus** und **IO::Socket** müssen auf dem System installiert sein.

# Installation

Das Modul in /HOMEPATH/FHEM/ ablegen und entsprechende Berechtigungen setzen. Wenn der FHEM-Nutzer fhem lautet, dann erfolgt dies mit:
`sudo chown fhem:fhem /HOMEPATH/FHEM/32_SiSi.pm`

Danach in FHEM mittels  `reload 32_SiSi.pm` das Modul einbinden.

# Funktionen

## Empfangen einer Nachrichten

Zu diesem Zeitpunkt können Nachrichten jeglicher Art empfangen werden. Dabei werden folgende Modul readings gesetzt.

* recvMessage: Für die empfangene Nachricht.
* recvSender: Für den Sender der Nachrichte.
* recvGroupID: Für die GruppenID in der die Nachricht verfasst wurde.
* recvTimestamp: Für den Zeitstempel, bei der die Nachricht abgesendet wurde.

Gesendet werden können Nachrichten an Empfänger wahlweise mit Anhang. Das Senden von Gruppennachrichten wird noch nicht unterstützt.

## Senden einer Nachricht

Eine Nachricht kann mittels des Set-Kommandos sendMessage gesendet werden. Dieses wird wie folgt angesprochen:

`Usage: set <NAME> sendMessage m="MESSAGE" r=RECIPIENT1,RECIPIENT2,RECIPIENTN [a="PATH1,PATH2,PATHN"]`

Die Nummer des Empfängers muss dabei mit Ländervorwahl sein. Also +49XXXX.

## Reconnect

Mittels
`set <NAME> reconnect`
wird die Verbindung zum DBus-Service neu aufgebaut.

## Attribute

* enable: [yes|no] Das Modul versucht eine Verbindung zum DBus Service `org.asamk.Signal` aufzubauen. Wenn Verbunden wechselt STATE auf *Connect*.
* DBusTimout: [60-500] Bei langsamen Systemen (RPI1) kann es zu reply-Timeouts kommen, vorallem wenn Nachrichten mit großen Anhängen gesendet werden. Angabe in Sekunden.

# Wichtig

Das Modul befindet sich noch in früher Entwicklungsphase. Fehlfunktionen daher nicht ausgeschlossen !
