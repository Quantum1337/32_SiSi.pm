package main;
use strict;
use warnings;

use Net::DBus;
use Net::DBus::Reactor;
use Net::DBus::Callback;
use Socket;
use POSIX ":sys_wait_h";

my %SiSi_sets = (
	"sendMessage"	=> "",
	"reconnect:noArg"   => ""
);

sub SiSi_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'SiSi_Define';
    $hash->{UndefFn}    = 'SiSi_Undef';
    $hash->{SetFn}      = 'SiSi_Set';
    $hash->{ShutdownFn} = 'SiSi_Shutdown';
    $hash->{ReadFn}     = 'SiSi_Read';
    $hash->{AttrFn}     = 'SiSi_Attr';
    $hash->{NotifyFn}   = 'SiSi_Notify';


    $hash->{AttrList} =
          "enable:no,yes " .
					"DBusTimeout " .
					"DBusService " .
					"DBusObject " .
          $readingFnAttributes;

    $hash->{parseParams} = 1;
}

my $attrChanged = 0;

sub SiSi_Define($$$) {
	my ($hash, $a, $h) = @_;

	if($init_done){

		$hash->{DBUS_OBJECT} = AttrVal($hash->{NAME},"DBusObject","/org/asamk/Signal");
		$hash->{DBUS_SERVICE} = AttrVal($hash->{NAME},"DBusService","org.asamk.Signal");

		if(AttrVal($hash->{NAME},"enable","no") eq "yes"){

			RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");

			if(!&SiSi_MessageDaemonRunning($hash)){
				&SiSi_startMessageDaemon($hash)
			}

			InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

		}else{
			$hash->{STATE} = "Disconnected";
		}
	}else{
		$hash->{STATE} = "Disconnected";
	}

	return
}

sub SiSi_Undef($$) {
	my ($hash, $arg) = @_;

	if(&SiSi_MessageDaemonRunning($hash)){
		&SiSi_stopMessageDaemon($hash);
	}

	RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");

	return undef;
}

sub SiSi_Shutdown($){
	my($hash) = @_;

	if(&SiSi_MessageDaemonRunning($hash)){
		&SiSi_stopMessageDaemon($hash);
	}

	RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");

	return;

}

sub SiSi_Set($$$) {
	my ($hash, $a, $h) = @_;

	if($a->[1] eq "reconnect"){

				if(AttrVal($hash->{NAME},"enable","no") eq "yes"){
					RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
					&SiSi_restartMessageDaemon($hash);
					InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);
				}else{
					return "Enable $hash->{NAME} first. Type 'attr $hash->{NAME} enable yes'"
				}

	}elsif($a->[1] eq "sendMessage"){

		 my $attachment = "NONE";
		 my $message = "";

		 if(!defined $h->{r} && (!defined $h->{m})){
			 return "Usage: set $hash->{NAME} $a->[1] m=\"MESSAGE\" r=RECIPIENT1,RECIPIENT2,RECIPIENTN [a=\"PATH1,PATH2,PATHN\"]"

		 }elsif($h->{r} !~ /^\+{1}[0-9]+(,\+{1}[0-9]+)*$/){

			 return "RECIPIENT must fullfil the following regex pattern: \+{1}[0-9]+(,\+{1}[0-9]+)*"

		 }else{

			 if(defined $h->{m}){
				 $message = $h->{m};
			 }

			 if(defined $h->{a}){
				 $attachment = $h->{a};
			 }

			 #Substitute \n with the \x1A "substitute" character
			 $message =~ s/\\n/\x1A/g;

			 syswrite($hash->{FH},"Send:Recipients:$h->{r},Attachments:$attachment,Message:$message\n");

			 return;

		 }

	}else{
		my @cList = keys %SiSi_sets;
		return "Unknown command $a->[1], choose one of " . join(" ", @cList);
	}

}

sub SiSi_Read($){
	my ( $hash ) = @_;

	my $buffer;
	my $sysreadReturn;
	my $curr_message;
	my @messages;

  $sysreadReturn = sysread($hash->{FH},$buffer,65536);

	if($sysreadReturn < 0 || !defined $sysreadReturn){
		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Error while reading data from child.");

		RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
		&SiSi_stopMessageDaemon($hash);
		InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

		return;
	}

	@messages = split(/\x0|\n|org.freedesktop./,$buffer);

	while(@messages){
		$curr_message = shift(@messages);

		if($curr_message =~ /^Received:Timestamp:([0-9]+),Sender:(\+{1}[0-9]+),GroupID:([0-9]+|NONE),Attachment:(\/.*\/attachments\/[0-9]+|NONE),Message:(.*)$/){

			my $timestamp = $1;
			my $sender = $2;
			my $groupID = $3;
			my $attachment = $4;
			my $message = $5;
			my $logMessage = "";

			$logMessage = $message;
			$message =~ s/\x1A/\n/g;
			$timestamp = strftime("%Y-%m-%d %H:%M:%S",localtime($timestamp/1000));

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "recvTimestamp", $timestamp);
			readingsBulkUpdate($hash, "recvMessage", $message);
			readingsBulkUpdate($hash, "recvSender", $sender);
			readingsBulkUpdate($hash, "recvGroupID", $groupID);
			readingsBulkUpdate($hash, "recvAttachment", $attachment);
			readingsEndUpdate($hash, 1);

			$logMessage =~ s/\x1A/\x20/g;

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - The message: '$logMessage' with timestamp: '$timestamp' was received from sender: '$sender' in group: '$groupID' and attachment: '$attachment'");

		}elsif($curr_message =~ /^Sended:Recipients:(\+{1}[0-9]+.*),Attachments:(\/.+|NONE),Message:(.*)$/){

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - The message: '$3' with attachment\(s\): '$2' was sended to recipient\(s\): '$1'");

		}elsif($curr_message =~ /^State:(.*)$/){

			$hash->{STATE} = "$1";

		}elsif($curr_message =~ /^DBus.Error.(.+)$/){

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - A DBus error occured: $1. Closing connection.");

			#RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
			#&SiSi_stopMessageDaemon($hash);
			#InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

		}elsif($curr_message =~ /^Log:([0-9]{1}),(.+)$/){

			Log3($hash->{NAME},$1,$2);

		}elsif($curr_message =~ /^$/){
			next;
		}else{

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - An unexpected error occured. Closing connection to DBus service $hash->{DBUS_SERVICE} $curr_message");

			RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
			&SiSi_restartMessageDaemon($hash);
			InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

	}

}

}

sub SiSi_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {

      if($attr_name eq "enable") {
				if($attr_value =~ /^yes$/) {

					my $hash = $defs{$name};

					if($init_done){
						if(!&SiSi_MessageDaemonRunning($hash)){

							RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
							&SiSi_startMessageDaemon($hash);
							InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

						}
					}
				}elsif($attr_value =~ /^no$/){

					my $hash = $defs{$name};

					&SiSi_stopMessageDaemon($hash);
					RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");

				}else{
					return "Invalid argument $attr_value to $attr_name. Must be yes or no.";
				}
			}elsif($attr_name eq "DBusTimeout") {
				if($attr_value =~ /^[0-9]+$/ && ($attr_value >= 60 && $attr_value <= 500)) {

					my $hash = $defs{$name};
					if(AttrVal($hash->{NAME},"enable","no") eq "yes"){


						RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
						$attrChanged = 1;
						InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

					}

				}else{

					return "Invalid argument $attr_value to $attr_name. Must be nummeric and between 60 and 500"

				}
			}

	}elsif($cmd eq "del"){
		if($attr_name eq "enable"){

			my $hash = $defs{$name};

			RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
			&SiSi_stopMessageDaemon($hash);

		}elsif($attr_name eq "DBusTimeout"){
			my $hash = $defs{$name};
			if(AttrVal($hash->{NAME},"enable","no") eq "yes"){

				RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
				$attrChanged = 1;
				InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);
			}

		}
	}
return undef
}

sub SiSi_Notify($$){
	my ($own_hash, $dev_hash) = @_;

	if(IsDisabled($own_hash->{NAME})){
		return ""
	}

	my $events = deviceEvents($dev_hash, 1);

	if($dev_hash->{NAME} eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})){

		$own_hash->{DBUS_OBJECT} = AttrVal($own_hash->{NAME},"DBusObject","/org/asamk/Signal");
		$own_hash->{DBUS_SERVICE} = AttrVal($own_hash->{NAME},"DBusService","org.asamk.Signal");

		if(AttrVal($own_hash->{NAME},"enable","no") eq "yes"){

			RemoveInternalTimer($own_hash,"SiSi_MessageDaemonWatchdog");

			if(!&SiSi_MessageDaemonRunning($own_hash)){
				&SiSi_startMessageDaemon($own_hash);
			}

			InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$own_hash);

		}else{
			$own_hash->{STATE} = "Disconnected";
		}
	}

	return

}

sub SiSi_startMessageDaemon($){
	my ($hash) = @_;

	my $child_pid;
	my $childsEnd;
	my $parentsEnd;

	if(socketpair($childsEnd, $parentsEnd, AF_UNIX, SOCK_STREAM, PF_UNSPEC)){
		$child_pid = fhemFork();
		if(!defined $child_pid){
			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Can't fork ! Maybe no memory left?");
			return 0;
		}
	}else{
			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Can't establish a socket pair!");
			return 0;
	}

	if (!$child_pid){
		#Here lives the child process
		sub msg_received();
		sub msg_send();

		my $child_hash = $hash;

		$0 = $child_hash->{NAME} . "_tx";

		close $parentsEnd;
		close STDIN;
		close STDOUT;
		close STDERR;

		$child_hash->{FD} = $childsEnd->fileno();
		$child_hash->{FH} = $childsEnd;

		open(STDIN,"<&$child_hash->{FD}") or die;
		open(STDOUT,">&$child_hash->{FD}") or die;
		open(STDERR,">&$child_hash->{FD}") or die;

		STDOUT->autoflush(1);
		STDERR->autoflush(1);

		#Connect to the DBUS Instance
		print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Trying to connect to DBus\' System Bus.\n");
  	my $DBus = Net::DBus->system;
		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Connected to DBus\' System Bus.\n");

		print("Log:5,$child_hash->{TYPE} $child_hash->{NAME} - Setting DBus Timeout to " . AttrVal($child_hash->{NAME},"DBusTimeout",60) . "s.\n");
		$DBus->timeout(AttrVal($child_hash->{NAME},"DBusTimeout",60) * 1000);

		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Trying to connect to DBus service $child_hash->{DBUS_SERVICE}.\n");
		my $signal_cli_service = $DBus->get_service($child_hash->{DBUS_SERVICE});
		my $signal_cli = $signal_cli_service->get_object($child_hash->{DBUS_OBJECT});
		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Connected to DBus service $child_hash->{DBUS_SERVICE}.\n");

		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Trying to listen to DBus-signal 'MessageReceived'.\n");
		$signal_cli->connect_to_signal('MessageReceived', \&msg_received);
		print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Listening to DBus-signal 'MessageReceived' on service $hash->{DBUS_SERVICE}.\n");

		#Not implemented in v0.5.6. But the functionality is in the master branch :)
		#$signal_cli->connect_to_signal('ReceiptReceived', \&recp_received);

		#Setting up an event Loop
		my $event_loop = Net::DBus::Reactor->main();
		$event_loop->add_read($child_hash->{FD},Net::DBus::Callback->new(method => \&msg_send, args => [$child_hash,$signal_cli]));
		#$event_loop->add_timeout(20000, Net::DBus::Callback->new(method => \&msg_timeout, args => [$child_hash]));

		#Let the parent know that the child is connected
		print("State:Connected\n");

		#Start the event loop
		$event_loop->run();
		exit;

		sub msg_received() {

			my ($timestamp,$sender,$groupID,$message,$attach) = @_;

			print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - A new message was received on DBus-signal 'MessageReceived'.\n");

			$groupID->[0] = "NONE" unless $groupID->[0];
			$attach->[0] = "NONE" unless $attach->[0];

			#Substitute \n with the \x1A "substitute" character
			$message =~ s/\n/\x1A/g;

			#Send the received data to the parent
			print("Received:Timestamp:$timestamp,Sender:$sender,GroupID:$groupID->[0],Attachment:$attach->[0],Message:$message\n");

		}

		sub msg_send(){
				my ($hash, $signal_cli) = @_;

				my $buffer;
				my @messages;
				my $curr_message;
				my $sysreadReturn;

			  $sysreadReturn = sysread($hash->{FH}, $buffer, 65536 );

				if($sysreadReturn < 0 || !defined $sysreadReturn){
					syswrite($hash->{FH},"Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Error while reading data from parent.\n");
					return;
				}

				@messages = split(/\n/,$buffer);

				while(@messages){
					$curr_message = shift(@messages);

					if($curr_message =~ /^Send:Recipients:(\+{1}[0-9]+.*),Attachments:(\/.+|NONE),Message:(.*)$/){

						my @attachment = ();
						my @recipients = split(/,/,$1);
						my $message = "";
						my $logMessage = "";

						if($2 ne "NONE"){
							@attachment = split(/,/,$2);;
						}

						if(defined $3){
							$message = $3;
							$logMessage = $3;

							$message =~ s/\x1A/\n/g;
							$logMessage =~ s/\x1A/\x20/g;
						}

						syswrite($hash->{FH},"Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Trying to send message to DBus method 'sendMessage' on service $child_hash->{DBUS_SERVICE}\n");

						$signal_cli->sendMessage($message,\@attachment,\@recipients);

						syswrite($hash->{FH},"Sended:Recipients:$1,Attachments:$2,Message:$logMessage\n");

					}else{
						next;
					}
			}
		}

		sub msg_timeout() {
			my ($hash) = @_;
			my $processID = `ps -eo uname,comm,pid | awk '/^signal-\+ java/{print \$3}'`;

			#if($processID =~ /^[0-9]+/){
				#syswrite($hash->{FH},"Log:3,ALIVE $processID\n");

			#}else{
				# syswrite($hash->{FH},"Log:3,DEAD $processID\n");
			#}

		}
	}

	close $childsEnd;

	$hash->{PID} = $child_pid;
	$hash->{FD} = $parentsEnd->fileno();
	$hash->{FH} = $parentsEnd;

  $selectlist{$hash->{NAME}} = $hash;

	return 1;
}

sub SiSi_restartMessageDaemon($){
	my ($hash) = @_;

	Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Reconnect to DBus service $hash->{DBUS_SERVICE}.");

	&SiSi_stopMessageDaemon($hash);
	if(&SiSi_startMessageDaemon($hash)){
	}else{
		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Reconnection to DBus service $hash->{DBUS_SERVICE} failed.");
	}
}

sub SiSi_stopMessageDaemon($){
	my ($hash) = @_;
	Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Closing connection to DBus service $hash->{DBUS_SERVICE}.");
	if(defined $hash->{FH} || defined $selectlist{$hash->{NANE}} || defined $hash->{FD} || defined $hash->{FH} || defined $hash->{PID}){

		if(defined $hash->{FH}){
			close($hash->{FH});
		}
		if(defined $selectlist{$hash->{NANE}}){
			delete($selectlist{$hash->{NANE}});
		}
		delete($hash->{FD});
		delete($hash->{FH});

		if(defined $hash->{PID}){

			Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Trying to kill PID '$hash->{PID}'.");

			if(kill(9,$hash->{PID})){

				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - PID '$hash->{PID}' killed.");

			}else{
				Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Killing PID '$hash->{PID}' failed. Maybe the process crashed due to an error?.");
			}

			delete($hash->{PID});
		}

		$hash->{STATE} = "Disconnected";
		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{DBUS_SERVICE} closed.");

	}else{
		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{DBUS_SERVICE} is already closed.");
	}

	return;
}

sub SiSi_MessageDaemonRunning($){
	my ($hash) = @_;

	if(!defined $hash->{PID}){
		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{DBUS_SERVICE} not established.");
		return 0;
	}

	if(!waitpid($hash->{PID},WNOHANG)){
		return 1;
	}else{
		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{DBUS_SERVICE} lost.");
		return 0;
	}
}

sub SiSi_MessageDaemonWatchdog($){
	my ($hash) = @_;

	if(&SiSi_MessageDaemonRunning($hash) && !$attrChanged){
		InternalTimer(gettimeofday() + 30,"SiSi_MessageDaemonWatchdog",$hash);
	}else{

		if($attrChanged){
			$attrChanged = 0;
		}

		RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
		&SiSi_restartMessageDaemon($hash);
		InternalTimer(gettimeofday() + 30,"SiSi_MessageDaemonWatchdog",$hash);

	}

}

1;
