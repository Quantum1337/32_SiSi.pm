package main;
use strict;
use warnings;

eval "use Net::DBus;1" or my $NETDBus = "Net::DBus";
eval "use Net::DBus::Reactor;1" or my $NETDBusReactor = "Net::DBus::Reactor";
eval "use Net::DBus::Callback;1" or my $NETDBusCallback = "Net::DBus::Callback";
use Socket;
use POSIX ":sys_wait_h";

my %SiSi_sets = (
	"message" => "",
	"msg" => "",
	"_msg" => "",
	"send" => "",
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
					"timeout " .
					"service " .
					"object " .
					"defaultRecipient " .
          $readingFnAttributes;

    $hash->{parseParams} = 1;
}

my $attrChanged = 0;

sub SiSi_Define($$$) {
	my ($hash, $a, $h) = @_;

	return "Error while loading $NETDBus. Please install $NETDBus" if $NETDBus;
	return "Error while loading $NETDBusReactor. Please install $NETDBusReactor" if $NETDBusReactor;
	return "Error while loading $NETDBusCallback. Please install $NETDBusCallback" if $NETDBusCallback;

	$Net::DBus::VERSION =~ /^([0-9]+)\.([0-9]+)\.[0-9]+$/;
	if($1 < 1 || $2 < 1){
		return "Please install Net::DBus in version 1.1.0 or higher. Your version is: $Net::DBus::VERSION"
	}

	$hash->{OBJECT} = AttrVal($hash->{NAME},"object","/org/asamk/Signal");
	$hash->{SERVICE} = AttrVal($hash->{NAME},"service","org.asamk.Signal");

	if($init_done && AttrVal($hash->{NAME},"enable","no") eq "yes"){

			RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");

			if(!&SiSi_MessageDaemonRunning($hash)){
				&SiSi_startMessageDaemon($hash)
			}

			InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);

	}

	$hash->{STATE} = "Disconnected";
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

	}elsif(($a->[1] eq "message") || ($a->[1] eq "msg") || ($a->[1] eq "_msg") || ($a->[1] eq "send") ){

		 my $attachment = "NONE";
		 my $text = "";
		 my $recipient = "";

		 if(!&SiSi_MessageDaemonRunning($hash)){

			 return "Enable $hash->{NAME} first. Type 'attr $hash->{NAME} enable yes'"

		 }elsif(!defined $h->{m} || $h->{m} eq ""){

			 return "Usage: set $hash->{NAME} $a->[1] m=\"MESSAGE\" [r=RECIPIENT1,RECIPIENT2,RECIPIENTN] [a=\"PATH1,PATH2,PATHN\"]"

		 }elsif(!defined $h->{r} && !defined AttrVal($hash->{NAME},"defaultRecipient",undef)){

			 return "Specify a RECIPIENT with r=RECIPIENT or set attr $hash->{NAME} defaultRecipient RECIPIENT"

		 }else{

			 if(defined $h->{r}){
				 if($h->{r} !~ /^\+{1}[0-9]+(,\+{1}[0-9]+)*$/){
					 return "RECIPIENT must fullfil the following regex pattern: \+{1}[0-9]+(,\+{1}[0-9]+)*"
				 }else{
				 	 $recipient = $h->{r};
			 	 }
			 }else{
				 $recipient = AttrVal($hash->{NAME},"defaultRecipient",undef);
			 }

			 if(defined $h->{m}){
				 $text = $h->{m};
			 }

			 if(defined $h->{a}){
				 $attachment = $h->{a};
			 }

			 #Substitute \n with the \x1A "substitute" character
			 $text =~ s/\\n/\x1A/g;

			 syswrite($hash->{FH},"Send:Recipients:$recipient,Attachments:$attachment,Text:$text\n");

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

	@messages = split(/\x00|\n/,$buffer);

	while(@messages){
		$curr_message = shift(@messages);

		if($curr_message =~ /^Received:Timestamp:([0-9]+),Sender:(\+{1}[0-9]+),GroupID:([0-9]+|NONE),Attachment:(\/.*\/attachments\/[0-9]+|NONE),Text:(.*)$/){

			my $timestamp = $1;
			my $sender = $2;
			my $groupId = $3;
			my $attachment = $4;
			my $text = $5;
			my $logText = "";

			$logText = $text;
			$text =~ s/\x1A/\n/g;
			$timestamp = strftime("%Y-%m-%d %H:%M:%S",localtime($timestamp/1000));

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "prevMsgTimestamp", ReadingsVal($hash->{NAME}, "msgTimestamp", undef)) if defined ReadingsVal($hash->{NAME}, "msgTimestamp", undef);
			readingsBulkUpdate($hash, "prevMsgText", ReadingsVal($hash->{NAME}, "msgText", undef)) if defined ReadingsVal($hash->{NAME}, "msgText", undef);
			readingsBulkUpdate($hash, "prevMsgSender", ReadingsVal($hash->{NAME}, "msgSender", undef)) if defined ReadingsVal($hash->{NAME}, "msgSender", undef);
			readingsBulkUpdate($hash, "prevMsgGroupId", ReadingsVal($hash->{NAME}, "msgGroupId", undef)) if defined ReadingsVal($hash->{NAME}, "msgGroupId", undef);
			readingsBulkUpdate($hash, "prevMsgAttachment", ReadingsVal($hash->{NAME}, "msgAttachment", undef)) if defined ReadingsVal($hash->{NAME}, "msgAttachment", undef);
			readingsEndUpdate($hash, 0);

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "msgTimestamp", $timestamp);
			readingsBulkUpdate($hash, "msgText", $text);
			readingsBulkUpdate($hash, "msgSender", $sender);
			readingsBulkUpdate($hash, "msgGroupId", $groupId);
			readingsBulkUpdate($hash, "msgAttachment", $attachment);
			readingsEndUpdate($hash, 1);

			$logText =~ s/\x1A/\x20/g;

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - The message: '$logText' with timestamp: '$timestamp' was received from sender: '$sender' in group: '$groupId' and attachment: '$attachment'");

		}elsif($curr_message =~ /^Sended:Recipients:(\+{1}[0-9]+.*),Attachments:(\/.+|NONE),Text:(.*)$/){

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - The message: '$3' with attachment\(s\): '$2' was sended to recipient\(s\): '$1'");

		}elsif($curr_message =~ /^State:(.*)$/){

			$hash->{STATE} = "$1";

		}elsif($curr_message =~ /^Log:([0-9]{1}),(.+)$/){

			Log3($hash->{NAME},$1,$2);

		}elsif($curr_message =~ /^$/){
			next;
		}else{

			Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - An unexpected error occured: $curr_message. Please inform the module owner. Closing connection to DBus service $hash->{SERVICE}.");

			RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
			&SiSi_stopMessageDaemon($hash);
			InternalTimer(gettimeofday() + 30,"SiSi_MessageDaemonWatchdog",$hash);

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
			}elsif($attr_name eq "timeout") {
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
			}elsif($attr_name eq "defaultRecipient") {
				if($attr_value =~ /^\+{1}[0-9]+(,\+{1}[0-9]+)*$/) {

					return undef;

				}else{

					return "Invalid argument $attr_value to $attr_name. Must fullfil the following regex pattern: \+{1}[0-9]+(,\+{1}[0-9]+)*"

				}
			}

	}elsif($cmd eq "del"){
		if($attr_name eq "enable"){

			my $hash = $defs{$name};

			RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
			&SiSi_stopMessageDaemon($hash);

		}elsif($attr_name eq "timeout"){
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

	if($dev_hash->{NAME} eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}) && AttrVal($own_hash->{NAME},"enable","no") eq "yes"){

			RemoveInternalTimer($own_hash,"SiSi_MessageDaemonWatchdog");

			if(!&SiSi_MessageDaemonRunning($own_hash)){
				&SiSi_startMessageDaemon($own_hash);
			}

			InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$own_hash);

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
		open(STDERR,">", "/dev/null") or die;

		STDOUT->autoflush(1);

		#Connect to the DBUS Instance
		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Trying to connect to DBus\' System Bus.\n");
  	my $DBus = Net::DBus->system;
		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Connected to DBus\' System Bus.\n");

		print("Log:5,$child_hash->{TYPE} $child_hash->{NAME} - Setting DBus Timeout to " . AttrVal($child_hash->{NAME},"timeout",60) . "s.\n");
		$DBus->timeout(AttrVal($child_hash->{NAME},"timeout",60) * 1000);

		print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Trying to connect to DBus service $child_hash->{SERVICE}.\n");

		my $signal_cli_service;
    eval{
			$signal_cli_service = $DBus->get_service($child_hash->{SERVICE}); 1
		} or do{
						if($@ =~ /^org\.freedesktop\.DBus\.Error\.TimedOut:.*: t(.+)$/){
							print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - T$1.\n");
						}elsif($@ =~ /^org\.freedesktop\.DBus\.Error\.NoReply: (.+)\. .*$/){
							print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - $1.\n");
						}else{
							print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - $@\n");
						}
						die;
		};

		my $signal_cli = $signal_cli_service->get_object($child_hash->{OBJECT});
		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Connected to DBus service $child_hash->{SERVICE}.\n");

		print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - Trying to listen to DBus-signal 'MessageReceived'.\n");
		$signal_cli->connect_to_signal('MessageReceived', \&msg_received);
		print("Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Listening to DBus-signal 'MessageReceived' on service $hash->{SERVICE}.\n");

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

			my ($timestamp,$sender,$groupId,$text,$attachment) = @_;

			print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - A new message was received on DBus-signal 'MessageReceived'.\n");

			$groupId->[0] = "NONE" unless $groupId->[0];
			$attachment->[0] = "NONE" unless $attachment->[0];

			#Substitute \n with the \x1A "substitute" character
			$text =~ s/\n/\x1A/g;

			#Send the received data to the parent
			print("Received:Timestamp:$timestamp,Sender:$sender,GroupID:$groupId->[0],Attachment:$attachment->[0],Text:$text\n");

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

					if($curr_message =~ /^Send:Recipients:(\+{1}[0-9]+.*),Attachments:(\/.+|NONE),Text:(.*)$/){

						my @attachment = ();
						my @recipients = split(/,/,$1);
						my $text = "";
						my $logText = "";

						if($2 ne "NONE"){
							@attachment = split(/,/,$2);;
						}

						if(defined $3){
							$text = $3;
							$logText = $3;

							$text =~ s/\x1A/\n/g;
							$logText =~ s/\x1A/\x20/g;
						}

						syswrite($hash->{FH},"Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Trying to send message to DBus method 'sendMessage' on service $child_hash->{SERVICE}\n");

						eval{
							$signal_cli->sendMessage($text,\@attachment,\@recipients); 1
						} or do{
										if($@ =~ /^org\.asamk\.signal\.AttachmentInvalidException:.*: (.+)$/){
											syswrite($hash->{FH},"Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Sending failed: $1.\n");
										}elsif($@ =~ /^org\.freedesktop\.dbus\.exceptions\.DBusExecutionException: (.+)$/){
											syswrite($hash->{FH},"Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Sending failed: $1 - Maybe wrong Number?\n");
										}else{
											syswrite($hash->{FH},"Log:3,$child_hash->{TYPE} $child_hash->{NAME} - Sending failed @1\n");
										}
										next;
						};

						syswrite($hash->{FH},"Sended:Recipients:$1,Attachments:$2,Text:$logText\n");

					}else{
						next;
					}
			}
		}

		sub msg_timeout() {
			my ($hash) = @_;
			#my $processID = `ps -eo uname,comm,pid | awk '/^signal-\+ java/{print \$3}'`;

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

	Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Reconnect to DBus service $hash->{SERVICE}.");

	&SiSi_stopMessageDaemon($hash);
	if(&SiSi_startMessageDaemon($hash)){
	}else{
		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Reconnection to DBus service $hash->{SERVICE} failed.");
	}
}

sub SiSi_stopMessageDaemon($){
	my ($hash) = @_;
	Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Closing connection to DBus service $hash->{SERVICE}.");
	if(defined $selectlist{$hash->{NANE}} || defined $hash->{FD} || defined $hash->{FH} || defined $hash->{PID}){

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
		Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{SERVICE} closed.");

	}else{
		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{SERVICE} is already closed.");
	}

	return;
}

sub SiSi_MessageDaemonRunning($){
	my ($hash) = @_;

	if(!defined $hash->{PID}){
		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{SERVICE} not established.");
		return 0;
	}

	if(!waitpid($hash->{PID},WNOHANG)){
		return 1;
	}else{
		Log3($hash->{NAME},4,"$hash->{TYPE} $hash->{NAME} - Connection to DBus service $hash->{SERVICE} lost.");
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
