package main;

use strict;
use warnings;

eval "use Net::DBus;1" or my $NETDBus = "Net::DBus";
eval "use Net::DBus::Reactor;1" or my $NETDBusReactor = "Net::DBus::Reactor";
eval "use Net::DBus::Callback;1" or my $NETDBusCallback = "Net::DBus::Callback";
use Socket;
use MIME::Base64;
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
					"defaultPeer " .
					"allowedPeer " .
          $readingFnAttributes;

    #$hash->{parseParams} = 1;
}

my $attrChanged = 0;

sub SiSi_Define($$$) {
	my ($hash, $def) = @_;

	return "Error while loading $NETDBus. Please install $NETDBus" if $NETDBus;
	return "Error while loading $NETDBusReactor. Please install $NETDBusReactor" if $NETDBusReactor;
	return "Error while loading $NETDBusCallback. Please install $NETDBusCallback" if $NETDBusCallback;

	$Net::DBus::VERSION =~ /^([0-9]+)\.([0-9]+)\.([0-9]+)$/;
	if(($1*100+$2*10+$3) < 110){
		return "Please install Net::DBus in version 1.1.0 or higher. Your version is: $Net::DBus::VERSION"
	}

	$hash->{VERSION} = "1.0";
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
	my ($hash, $name, $opt, @args) = @_;

	if($opt eq "reconnect"){

				if(AttrVal($hash->{NAME},"enable","no") eq "yes"){
					RemoveInternalTimer($hash,"SiSi_MessageDaemonWatchdog");
					&SiSi_restartMessageDaemon($hash);
					InternalTimer(gettimeofday() + 5,"SiSi_MessageDaemonWatchdog",$hash);
				}else{
					return "Enable $hash->{NAME} first. Type 'attr $hash->{NAME} enable yes'"
				}

	}elsif(($opt eq "message") || ($opt eq "msg") || ($opt eq "_msg") || ($opt eq "send") ){

		return "Usage: set $hash->{NAME} send|msg|_msg|message [@<Recipient1> ... @<RecipientN>] [@#<GroupId1> ... @#<GroupIdN>] [&<Attachment1> ... &<AttachmentN>] [<Text>]" if (int(@args) == 0); # Only Attachment ??
		return "Enable $hash->{NAME} first. Type 'attr $hash->{NAME} enable yes'" if(!&SiSi_MessageDaemonRunning($hash));

		my @recipients = ();
		my @groupIdsEnc = ();
		my @attachments = ();
		my $text = "";

		while(my $curr_arg = shift @args){

			if($curr_arg =~ /^\@([^\#].*)$/){
				push(@recipients,$1);
			}elsif($curr_arg =~ /^\@\#(.*)$/){
				push(@groupIdsEnc,$1);
			}elsif($curr_arg =~ /^\&(.*)$/){
				push(@attachments,$1);
			}else{
				unshift(@args,$curr_arg);
				last;
			}

		}
		return "Not enough arguments. Specify a Recipient, a GroupId or set the defaultPeer attribute" if(((int(@recipients) == 0) && (int(@groupIdsEnc) == 0)) && (!defined AttrVal($hash->{NAME},"defaultPeer",undef)));

		my @peers = split(/,/,AttrVal($hash->{NAME},"defaultPeer",undef));

		while(my $curr_arg = shift @peers){
			if($curr_arg =~ /^\+{1}[0-9]+$/){
				push(@recipients,$curr_arg);
			}elsif($curr_arg =~ /^[a-z,A-Z,0-9,\+,\/]{22}==$/){
				push(@groupIdsEnc,$curr_arg);
		  }
		}

		return "A Recipient is not valid. Note that you have to specify the country code e.g. +49... for germany" if(join(",",@recipients) !~ /^(\+{1}[0-9]+)*(,\+{1}[0-9]+)*$/);
		return "Specify either a message text or an attachment" if((int(@attachments) == 0) && (int(@args) == 0));

		$text = join(" ", @args);

		#Substitute \n with the \x1A "substitute" character
		$text =~ s/\n/\x1A/g;
		while(my $curr_recipient = shift @recipients){
			syswrite($hash->{FH},"Send:$curr_recipient\x1F\x1F".join(",",@attachments)."\x1F$text\n");
		}

		while(my $curr_groupIdEnc = shift @groupIdsEnc){
			syswrite($hash->{FH},"Send:\x1F$curr_groupIdEnc\x1F".join(",",@attachments)."\x1F$text\n");
		}

	}else{
		my @cList = keys %SiSi_sets;
		return "Unknown command $opt, choose one of " . join(" ", @cList);
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

	@messages = split(/\n/,$buffer);

	while(@messages){
		$curr_message = shift(@messages);

		if($curr_message =~ /^Received:([0-9]+)\x1F(\+{1}[0-9]+)\x1F(.*)\x1F(.*)\x1F(\/.*\/attachments\/[0-9]+|NONE)\x1F(.*)$/){

			my $timestamp = $1;
			my $sender = $2;
			my $groupId = $3;
			my $groupName = $4;
			my $attachment = $5;
			my $text = $6;
			my $logText = "";

			$logText = $text;
			$text =~ s/\x1A/\n/g;
			$timestamp = strftime("%Y-%m-%d %H:%M:%S",localtime($timestamp/1000));

			my $allowedPeer = AttrVal($hash->{NAME},"allowedPeer",undef);
			my $senderRegex = quotemeta($sender);
			my $groupIdRegex = quotemeta($groupId);

			if(!defined $allowedPeer || $allowedPeer =~ /^.*$senderRegex.*$/ || $allowedPeer =~ /^.*$groupIdRegex.*$/){

				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "prevMsgTimestamp", ReadingsVal($hash->{NAME}, "msgTimestamp", undef)) if defined ReadingsVal($hash->{NAME}, "msgTimestamp", undef);
				readingsBulkUpdate($hash, "prevMsgText", ReadingsVal($hash->{NAME}, "msgText", undef)) if defined ReadingsVal($hash->{NAME}, "msgText", undef);
				readingsBulkUpdate($hash, "prevMsgSender", ReadingsVal($hash->{NAME}, "msgSender", undef)) if defined ReadingsVal($hash->{NAME}, "msgSender", undef);
				readingsBulkUpdate($hash, "prevMsgGroupName", ReadingsVal($hash->{NAME}, "msgGroupName", undef)) if defined ReadingsVal($hash->{NAME}, "msgGroupName", undef);
				readingsBulkUpdate($hash, "prevMsgGroupId", ReadingsVal($hash->{NAME}, "msgGroupId", undef)) if defined ReadingsVal($hash->{NAME}, "msgGroupId", undef);
				readingsBulkUpdate($hash, "prevMsgAttachment", ReadingsVal($hash->{NAME}, "msgAttachment", undef)) if defined ReadingsVal($hash->{NAME}, "msgAttachment", undef);
				readingsEndUpdate($hash, 0);

				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "msgTimestamp", $timestamp);
				readingsBulkUpdate($hash, "msgText", $text);
				readingsBulkUpdate($hash, "msgSender", $sender);
				readingsBulkUpdate($hash, "msgGroupName", $groupName);
				readingsBulkUpdate($hash, "msgGroupId", $groupId);
				readingsBulkUpdate($hash, "msgAttachment", $attachment);
				readingsEndUpdate($hash, 1);

				$logText =~ s/\x1A/\x20/g;

				Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - The message: '$logText' with timestamp: '$timestamp' was received from sender: '$sender' in group: '$groupName ($groupId)' and attachment: '$attachment'");
			}else{
				Log3($hash->{NAME},3,"$hash->{TYPE} $hash->{NAME} - UNAUTHORIZED message: '$logText' with timestamp: '$timestamp' was received from sender: '$sender' in group: '$groupName ($groupId)' and attachment: '$attachment'");
			}
		}elsif($curr_message =~ /^Sent:(.*)\x1F(.*)\x1F(.*)\x1F(.*)\x1F(.*)\x1F(.*)\x1F(.*)$/){

			my $result = $1;
			my $recipient = $2;
			my $groupId = $3;
			my $groupName = $4;
			my $attachment = $5;
			my $text = $6;
			my $errorText = $7;

			delete $hash->{sentMsgResult} if(defined $hash->{sentMsgResult});
			delete $hash->{sentMsgRecipient} if(defined $hash->{sentMsgRecipient});
			delete $hash->{sentMsgGroupId} if(defined $hash->{sentMsgGroupId});
			delete $hash->{sentMsgGroupName} if(defined $hash->{sentMsgGroupName});
			delete $hash->{sentMsgAttachment} if(defined $hash->{sentMsgAttachment});
			delete $hash->{sentMsgText} if(defined $hash->{sentMsgText});
			delete $hash->{sentMsgError} if(defined $hash->{sentMsgError});


			$hash->{sentMsgResult} = $result;
			$hash->{sentMsgRecipient} = $recipient if($recipient);
			$hash->{sentMsgGroupId} = $groupId if($groupId);
			$hash->{sentMsgGroupName} = $groupName if($groupName);
			$hash->{sentMsgAttachment} = $attachment if($attachment);
			$hash->{sentMsgText} = $text if($text);
			$hash->{sentMsgError} = $errorText if($errorText);


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
					if((AttrVal($hash->{NAME},"enable","no")) eq "yes" && ($hash->{STATE} eq "Connected")){

						syswrite($hash->{FH},"Attr:Timeout,$attr_value");

					}

				}else{

					return "Invalid argument $attr_value to $attr_name. Must be nummeric and between 60 and 500"

				}
			}elsif($attr_name eq "defaultPeer") {
  		  if($attr_value =~ /^(\+{1}[0-9]+|[a-z,A-Z,0-9,\+,\/]{22}==){1}(,(\+{1}[0-9]+|[a-z,A-Z,0-9,\+,\/]{22}==))*$/){
					return undef;

				}else{

					return "Invalid argument $attr_value to $attr_name. Must be one or more valid recipient(s) or groupId(s)"

				}
			}elsif($attr_name eq "allowedPeer") {
				if($attr_value =~ /^(\+{1}[0-9]+|[a-z,A-Z,0-9,\+,\/]{22}==){1}(,(\+{1}[0-9]+|[a-z,A-Z,0-9,\+,\/]{22}==))*$/){

					return undef;

				}else{

					return "Invalid argument $attr_value to $attr_name. Must be one or more valid recipient(s) or groupId(s)"

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

				syswrite($hash->{FH},"Attr:Timeout,60");

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
		my $child_hash = $hash;
		$0 = $child_hash->{NAME} . "_tx";

		$child_hash->{DBUS}->{RECEIVED}->{MESSAGE} = sub {

			my ($timestamp,$sender,$groupId,$text,$attachment) = @_;

			my $groupIdEnc = "NONE";
			my $groupName = "NONE";

			print("Log:4,$child_hash->{TYPE} $child_hash->{NAME} - A new message was received on DBus-signal 'MessageReceived'.\n");

			#Encode GroupId in Base64
			if(@$groupId > 0){
				$groupIdEnc = encode_base64((join '', map chr, @$groupId),"");
				$groupName = $child_hash->{DBUS}->{OBJECT}->getGroupName($groupId);
			}

			$attachment->[0] = "NONE" unless $attachment->[0];

			#Substitute \n with the \x1A "substitute" character
			$text =~ s/\n/\x1A/g;

			#Send the received data to the parent
			print("Received:$timestamp\x1F$sender\x1F$groupIdEnc\x1F$groupName\x1F$attachment->[0]\x1F$text\n");

		};

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
		&SiSi_connectToDBus($child_hash);
		&SiSi_connectToDBusService($child_hash);
		&SiSi_connectToDBusObject($child_hash);

		exit &SiSi_childMain($child_hash);

		sub SiSi_childMain($){
			my ($hash) = @_;

			syswrite($hash->{FH},"Log:4,$hash->{TYPE} $hash->{NAME} - Trying to listen to DBus-signal 'MessageReceived'.\n");
			$hash->{DBUS}->{OBJECT}->connect_to_signal('MessageReceived', $hash->{DBUS}->{RECEIVED}->{MESSAGE});
			syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Listening to DBus-signal 'MessageReceived' on service $hash->{SERVICE}.\n");

			#Not implemented in v0.5.6. But the functionality is in the master branch :)
			#$signal_cli->connect_to_signal('ReceiptReceived', \&recp_received);

			#Setting up an event Loop
			$hash->{DBUS}->{REACTOR} = Net::DBus::Reactor->main();
			$hash->{DBUS}->{REACTOR}->add_read($hash->{FD},Net::DBus::Callback->new(method => \&SiSi_childRead, args => [$hash]));
			#$event_loop->add_timeout(20000, Net::DBus::Callback->new(method => \&SiSi_SignalDaemonWatchdog, args => [$child_hash]));

			#Let the parent know that the child is connected
			syswrite($hash->{FH},"State:Connected\n");

			#Start the event loop
			$hash->{DBUS}->{REACTOR}->run();

		}

		sub SiSi_connectToDBus($){
			my ($hash) = @_;

			syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Trying to connect to DBus\' System Bus.\n");
	  	$hash->{DBUS}->{BUS} = Net::DBus->system;
			syswrite($hash->{FH},"Log:4,$hash->{TYPE} $hash->{NAME} - Connected to DBus\' System Bus.\n");

			syswrite($hash->{FH},"Log:5,$hash->{TYPE} $hash->{NAME} - Setting DBus Timeout to " . AttrVal($hash->{NAME},"timeout",60) . "s.\n");
			$hash->{DBUS}->{BUS}->timeout(AttrVal($hash->{NAME},"timeout",60) * 1000);

		}

		sub SiSi_connectToDBusService($){
			my ($hash) = @_;

			syswrite($hash->{FH},"Log:4,$hash->{TYPE} $hash->{NAME} - Trying to connect to DBus service $hash->{SERVICE}.\n");

	    eval{
				$hash->{DBUS}->{SERVICE} = $hash->{DBUS}->{BUS}->get_service($hash->{SERVICE}); 1
			} or do{
							if($@ =~ /^org\.freedesktop\.DBus\.Error\.TimedOut:.*: t(.+)$/){
								syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Failed to connect to DBus service $hash->{SERVICE}: T$1.\n");
							}elsif($@ =~ /^org\.freedesktop\.DBus\.Error\.NoReply: (.+)\. .*$/){
								syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Failed to connect to DBus service $hash->{SERVICE}: $1.\n");
							}else{
								syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Failed to connect to DBus service $hash->{SERVICE}: $@\n");
							}
							die;
			};

			syswrite($hash->{FH},"Log:4,$hash->{TYPE} $hash->{NAME} - Connected to DBus service $hash->{SERVICE}.\n");

		}

		sub SiSi_connectToDBusObject($){
			my ($hash) = @_;

			syswrite($hash->{FH},"Log:4,$hash->{TYPE} $hash->{NAME} - Trying to connect to DBus Object $hash->{OBJECT}.\n");
			$hash->{DBUS}->{OBJECT} = $hash->{DBUS}->{SERVICE}->get_object($hash->{OBJECT});
			syswrite($hash->{FH},"Log:4,$hash->{TYPE} $hash->{NAME} - Connected to DBus Object $hash->{OBJECT}.\n");

		}

		sub SiSi_childRead(){
				my ($hash) = @_;

				my $buffer;
				my @messages;
				my $curr_message;
				my $sysreadReturn;

			  $sysreadReturn = sysread($hash->{FH}, $buffer, 65536 );

				if($sysreadReturn < 0 || !defined $sysreadReturn){
					syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Error while reading data from parent.\n");
					return;
				}

				@messages = split(/\n/,$buffer);

				while(@messages){
					$curr_message = shift(@messages);

					if($curr_message =~ /^Send:(.*)\x1F(.*)\x1F(.*)\x1F(.*)$/){

						my @attachment = ();
						my @recipients = "";
						my $text = "";
						my $logText = "";
						my $GroupIdEnc = "";
						my @groupId = "";
						my $groupName = "";

						@recipients = split(/,/,$1) if(defined $1);
						$GroupIdEnc = $2 if(defined $2);
						@attachment = split(/,/,$3) if(defined $3);

						if(defined $4){
							$text = $4;
							$logText = $4;

							$text =~ s/\x1A/\n/g;
							$logText =~ s/\x1A/\x20/g;
						}

						if(!$GroupIdEnc){
							syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Trying to send message to DBus method 'sendMessage' on service $hash->{SERVICE}\n");

							eval{
								$hash->{DBUS}->{OBJECT}->sendMessage($text,\@attachment,\@recipients); 1
							} or do{
											my $errorText = "";
											if($@ =~ /^org\.asamk\.signal\.AttachmentInvalidException:.*: (.+)$/){
												$errorText = $1;
											}elsif($@ =~ /^org\.freedesktop\.dbus\.exceptions\.DBusExecutionException: (.+)$/){
												$errorText = $1 . " - Maybe wrong Number?"
											}else{
												$errorText = $@;
											}
											syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Failed to send message: $errorText\n");
											syswrite($hash->{FH},"Sent:FAILED\x1F".join(",",@recipients)."\x1F$GroupIdEnc\x1F$groupName\x1F".join(",",@attachment)."\x1F$text\x1F$errorText\n");
											next;
										};
							syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - The message: '$logText' with attachment\(s\): '".join(",",@attachment)."' was sent to recipient\(s\): '".join(",",@recipients)."'\n");
						}else{

							my @chars = split //, decode_base64($GroupIdEnc);
							@groupId = map ord, @chars;

							syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Trying to send group message to DBus method 'sendGroupMessage' on service $hash->{SERVICE}\n");

							eval{
								$hash->{DBUS}->{OBJECT}->sendGroupMessage($text,\@attachment,\@groupId); 1
							} or do{
											my $errorText = "";
											if($@ =~ /^org\.asamk\.signal\.AttachmentInvalidException:.*: (.+)$/){
												$errorText = $1;
											}elsif($@ =~ /^org.asamk.signal.GroupNotFoundException: (.+)$/){
												$errorText = $1;
											}else{
												$errorText = $@;
											}
											syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - Failed to send group message: $errorText.\n");
											syswrite($hash->{FH},"Sent:FAILED\x1F".join(",",@recipients)."\x1F$GroupIdEnc\x1F$groupName\x1F".join(",",@attachment)."\x1F$text\x1F$errorText\n");
											next;
										};
							$groupName = $hash->{DBUS}->{OBJECT}->getGroupName(\@groupId);
							syswrite($hash->{FH},"Log:3,$hash->{TYPE} $hash->{NAME} - The message: '$logText' with attachment\(s\): '".join(",",@attachment)."' was sent to group: '$GroupIdEnc'\n");
						}

						syswrite($hash->{FH},"Sent:SUCCESS\x1F".join(",",@recipients)."\x1F$GroupIdEnc\x1F$groupName\x1F".join(",",@attachment)."\x1F$logText\x1F\n");

					}elsif($curr_message =~ /^Attr:Timeout,([0-9]+)$/){

						syswrite($hash->{FH},"Log:5,$hash->{TYPE} $hash->{NAME} - Setting DBus Timeout to " . $1 . "s.\n");
						$hash->{DBUS}->{BUS}->timeout($1 * 1000);

					}else{
						next;
					}
			}
		}

		sub SiSi_SignalDaemonWatchdog() {
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
	if(defined $selectlist{$hash->{NAME}} || defined $hash->{FD} || defined $hash->{FH} || defined $hash->{PID}){

		if(defined $hash->{FH}){
			close($hash->{FH});
		}
		if(defined $selectlist{$hash->{NAME}}){
			delete($selectlist{$hash->{NAME}});
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

=pod
=begin html

<a name="SiSi"></a>
<h3>SiSi</h3>
<ul>
    <i>[Si]gnal [Si]cherer Messenger</i> is an encrypted communications application
		for <a href="https://github.com/signalapp/Signal-Android">Android</a> and
		<a href="https://github.com/signalapp/Signal-iOS">iOS</a>. Not only the
		mobile applications, also the <a href="https://github.com/signalapp/Signal-Server">Server</a>
		is free and open source.<br><br>
		This module makes use of <a href="https://github.com/AsamK/signal-cli">signal-cli</a>s
		DBus interface. Make sure signal-cli ist installed and configured properly on your FHEM host system.
		Look at <a href="https://github.com/AsamK/signal-cli/wiki/DBus-service">this</a>,
		<a href="https://forum.fhem.de/index.php/topic,84996.0.html">this</a> and
		<a href="https://github.com/Quantum1337/32_SiSi.pm/blob/master/README.md">that</a>
		to get further help.
    <br><br>
    <a name="SiSidefine"></a>
    <b>Define</b>
		<br><br>
    <ul>
        <code>define &lt;name&gt; SiSi</code>
    </ul>
    <br>
    <a name="SiSiset"></a>
    <b>Set</b><br>
    <ul>
        <ul>
              <li><i>message|msg|_msg|send [@&lt;Recipient1> ... @&lt;RecipientN>] [@#&lt;GroupId1&gt; ... @#&lt;GroupIdN&gt;] [&&lt;Attachment1&gt; ... &&lt;AttachmentN&gt;] [&lt;Text&gt;]</i><br>
              Sends a message to recipient(s) or group(s). Optional with attachment(s) and/or a text.
							Recipient(s) have to be given with country code e.g. +49 for germany.
							Valid GroupId(s) must end with two equal signs (==), because every GroupId is a Base64 encoded 128-Bit value.
							If neither a recipient nor a group was given, the value in the attribute
							defaultPeer will be used.
							<br><br>
							Example: set &lt;name&gt; msg @+491234567 Exampletext<br>
							This command will send a message to the recipient @+491234567 with a text
							Exampletext
							<br><br>
							Example: set &lt;name&gt; send @+491234567 @#abcdefgh12345== &/PATH/TO/FILE Exampletext<br>
							This command will send a message to the recipient +491234567 and the group abcdefgh12345==
							with an attachment FILE and the text Exampletext.
							</li>
							<li><i>reconnect</i><br>
							Initiates a reconnect to the siganl-clis DBus service.
							</li>
        </ul>
    </ul>
    <br>
    <a name="SiSiattr"></a>
    <b>Attributes</b>
    <ul>
        <ul>
						<li><i>defaultPeer</i><br>
								If neither a recipient nor a group was given with the send commands,
								the recipient(s) and/or groupId(s) given with this attribute will be used.
						</li>
						<li><i>allowedPeer</i><br>
							  Comma separated list of recipient(s) and/or groupId(s), allowed to
								update the msg.* readings and trigger new events when receiving a new message.
								<b>If the attribute is not defined, everyone is able to trigger new events!!</b>
						</li>
            <li><i>enable [yes|no]</i><br>
                Set this attribute to yes, to initiate a connection to signal-clis DBus service<br>
            </li>
						<li><i>timeout [60s-500s]</i><br>
                On slower systems, it is possible that the DBus Service will throw reply errors,
								when sending large attachments. Increase this value, to fix this problem.<br>
            </li>
        </ul>
    </ul>
		<br>
    <a name="SiSireadings"></a>
    <b>Readings</b>
    <ul>
        <ul>
						<li><i>msgText</i><br>
							Text of the last received message.
						</li>
            <li><i>msgSender</i><br>
							Sender of the last received message.
            </li>
						<li><i>msgGroupId</i><br>
							128-Bit base64 encoded group identifier of the last received message. If a message was not sent
							within a group, this reading will have the value NONE.
            </li>
						<li><i>msgGroupName</i><br>
							Group name of the last received message. If a message was not sent
							within a group, this reading will have the value NONE.
            </li>
						<li><i>msgTimestamp</i><br>
							Timestamp of the last received message.
            </li>
						<li><i>msgAttachment</i><br>
							Attachment of the last received message. This reading will hold
							the path, where the received attachment was saved. If a message was
							not sent with an attachment, this reading will have the value NONE.
            </li>
						<br>
						<br>
						<li><i>prevMsgText</i><br>
							Text of the previous received message.
						</li>
            <li><i>prevMsgSender</i><br>
							Sender of the previous received message.
            </li>
						<li><i>prevMsgGroupId</i><br>
							128-Bit base64 encoded group identifier of the previous received message. If a message was not sent
							within a group, this reading will have the value NONE.
            </li>
						<li><i>prevMsgGroupName</i><br>
							Group name of the previous received message. If a message was not sent
							within a group, this reading will have the value NONE.
            </li>
						<li><i>prevMsgTimestamp</i><br>
							Timestamp of the previous received message.
            </li>
						<li><i>prevMsgAttachment</i><br>
							Attachment of the previous received message. This reading will hold
							the path, where the received attachment was saved. If a message was
							not sent with an attachment, this reading will have the value NONE.
            </li>
						<br>
						<br>
						<li><b>NOTE: All prev... readings are not triggering events!</b><br>
            </li>
        </ul>
    </ul>
</ul>
=end html
=cut
