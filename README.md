# 32_SiSi.pm
Ein FHEM Modul für den quelloffenen Messenger "[Si]gnal - [Si]cherer Messenger"

# Einleitung

Das Modul liefert eine FHEM-DBus-Schnittstelle zum Kommandozeileninterface [signal-cli](https://github.com/AsamK/signal-cli) des Messengers [Signal](https://signal.org/). Signal ist ein sicherer, freier und quelloffener Messenger Dienst. Sowohl die [Clienten](https://github.com/signalapp) als auch der [Server](https://github.com/signalapp/Signal-Server) sind für jedermann frei einsehbar. Das Protokoll zur E2E-Verschlüsselung ist ebenfalls frei und quelloffenen.

Nur Unterstützung für Linux!

# Vorbereitungen

[signal-cli](https://github.com/AsamK/signal-cli) muss im [Daemon-Modus](https://github.com/AsamK/signal-cli/wiki/DBus-service) eingerichtet werden. Es müssen die DBus Konfiguration/Services und die systemd-Services wie unter **"System Bus"** beschrieben angelegt werden.

### Hervorhebungen

* Die Bibliothek jni/unix-java.so muss auf dem System installiert sein (Debian: libunixsocket-java ArchLinux: libmatthew-unix-java (AUR)).
* Der Nutzer "signal-cli" muss angelegt sein.
* Wenn schon eine Nummer registriert ist, liegt im Verzeichnis `~/.config/signal` ein Ordner "data", der den privaten Schlüssel der registrierten Nummer enthält. Diese muss rekursiv nach  `/var/lib/signal-cli/` kopiert werden. Danach müssen die Rechte auf den Nutzer signal-cli übertragen werden: `sudo chown -R signal-cli:signal-cli /var/lib/signal-cli/data`
* Das Modul unterstützt momentan noch **nicht** den DBus "Session Bus", deshalb ist die Einrichtung des **"System Bus"** zwingend erforderlich.
* Die Dateien, die im oben verlinkten Wiki benötigt werden, finden sich hier [hier](https://github.com/AsamK/signal-cli/tree/master/data)

Ob alles richtig eingerichtet wurde, kann mit

`dbus-send --system --type=method_call --print-reply --dest="org.asamk.Signal" /org/asamk/Signal org.asamk.Signal.sendMessage string:MessageText array:string: string:RECIPIENT`

überprüft werden. Dies kann beim ersten versuch - je nach System (RPI1) - mehrere Minuten dauern. Dies ist deshalb der Fall, da systemd den Prozess zunächst startet und hierfür die java Laufzeitumgebung geladen werden muss. Es wird dann eine Nachricht mit dem Inhalt "MessageText" an die Nummer "RECIPIENT" gesendet. Jede weitere Nachricht mithilfe des Befehl sollte in wenigen Sekunden ausgeführt sein.

# Abhängigkeiten

Das Perl Modul **Net::DBus** in der Version >= 1.1.0 muss auf dem System installiert sein. Die installierte Version kann mit: `perl -MNet::DBus -le 'print $Net::DBus::VERSION'` überprüft werden.

# Installation

Das Modul in /HOMEPATH/FHEM/ ablegen und entsprechende Berechtigungen setzen. Wenn der FHEM-Nutzer fhem lautet, dann erfolgt dies mit:
`sudo chown fhem:fhem /HOMEPATH/FHEM/32_SiSi.pm`

Danach in FHEM mittels  `reload 32_SiSi.pm` das Modul einbinden.

# Anmerkungen

## Funktionen

Siehe commandref.

## MIME

Sollte der gesendete Anhang (bsp. jpeg-Bild) nicht direkt im Chatverlauf angezeigt werden, sondern nur durch einen zusätzlichen Tap auf ein Datei-Icon. So muss das Paket **shared-mime-info** installiert werden, damit signal-cli die MIME Informationen setzen kann.

## DBus und systemd Timeouts

Gerade auf langsamen Systemen kann es zu Zeitüberschreitungen während des Starts des Daemons bzw. wärend dem Versenden von Nachrichten mit großen Anhängen kommen. Auf einem RPI1 dauert der Start mitunter 5 Minuten.

* Sollte systemd eine Zeitüberschreitung während des Starts melden, muss folgende Zeile in der `signal.service` unter `/etc/systemd/system` bei `[Service]` eingetragen werden: `TimeoutStartSec = VALUE_IN_SEC`. Danach `sudo systemctl daemon-reload` ausführen um die Änderung wirksam zu machen.
* Sollte das Modul den Fehler: `A DBus error occured: TimedOut: Failed to activate service 'org.asamk.Signal': timed out (service_start_timeout=25000ms). Closing connection.` bringen und sich dadurch öfter neu verbinden, kann die Zeile `<limit name="service_start_timeout">VaLUE_IN_MS</limit>` in der Datei `/etc/dbus-1/system.d/org.asamk.Signal.conf` vor `</busconfig>` eingetragen werden. Danach `sudo systemctl reload dbus.service` ausführen um die Änderung wirksam zu machen.
* Sollte das Modul den Fehler: `A DBus error occured: NoReply: Did not receive a reply. Possible causes include: the remote application did not send a reply, the message bus security policy blocked the reply, the reply timeout expired, or the network connection was broken.. Closing connection.` bringen, sollte das Attribut "timeout" entsprechend gesetzt werden.

# !!Wichtig!!

Das Modul befindet sich noch in früher Entwicklungsphase. Fehlfunktionen daher nicht ausgeschlossen !
