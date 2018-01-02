use Time::HiRes qw( sleep );
use feature "switch";
use JSON;
use constant {
    owner => "ashiudo",
    DEBUG => 0,
};

no warnings 'experimental';
BEGIN { $^W = 0 }; #disable warnings

our $httpref;
our $t = qr/^\./; #trigger

if( exists &weechat::register ) {
    my $SCRIPT_NAME = "sportsstatsbot";
    if( weechat::register( $SCRIPT_NAME, "Ashiudo", "0.81", "BEER-WARE", "look up nhl stats", "", "" ) ) {
        weechat::hook_signal("*,irc_in2_privmsg", "weechat_pre", "");
        weechat::hook_config("plugins.var.perl.$SCRIPT_NAME.*", "weechat_get_conf_cb", "");
        weechat_get_conf_cb();
    }
} else {
    require Irssi;
    Irssi::signal_add("event privmsg", "irssi_pre");
    Irssi::signal_add_last("setup reread", "irssi_get_conf_cb");
    irssi_get_conf_cb();
}

sub weechat_pre {
    my( $data, $signal, $signal_data ) = @_;
    $signal_data =~ /:?(?<nick>.*?)!(?<host>.*?) (?<command>.*?) (?<target>.*?) :?(?<text>.*)/;
    my %h = %+;
    return if( $h{text} !~ /${t}\w/ );
    $h{server} = (split( ",", $signal ))[0];

    if( weechat::info_get( "irc_is_channel", "$h{server},$h{target}" ) ) {
        return if( $fp{"$h{target}$h{server}"} && $fp{"$h{target}$h{server}"} > time );
        if( $h{text} !~ /^(.\w+)2( .*|$)/ ) {
            my $nicks = weechat::infolist_get( "irc_nick", "", "$h{server},$h{target}" );
            while( weechat::infolist_next( $nicks ) ) {
                #my $fields = weechat::infolist_fields( $nicks );
                #weechat::print "", "nicks: $nicks -- fields: $fields";
                my $host = weechat::infolist_string( $nicks, "host" );
                my $nick = weechat::infolist_string( $nicks, "name" );
                if( !$h{scorebot} && $nick =~ /^scores$/i ) {
                    $h{scorebot} = (!$host || $host =~ /^~?johne@.*/i); }
                if( !$h{goalbot} && $nick =~ /^goal[bn]ot$/i ) {
                    $h{goalbot} = (!$host || $host =~ /~?johne@.*/i); }
                last if( $h{scorebot} && $h{goalbot} );
            }
            weechat::infolist_free($nicks);
        } else {
            $_ = "$1$2";
            $h{text} = $_ if( $h{text} !~ /${t}(stats|last|next)/i );
        }
    } else {
        return if( $fp{"priv$h{server}"} > time );
        $fp{"priv$h{server}"} = time + 3;
        $h{target} = $h{nick};
    }
    $h{buffer} = weechat::info_get("irc_buffer", "$h{server},$h{target}");
    event_privmsg( \%h );
}

sub irssi_pre {
    my ($shash, $ircdata, $nick, $mask) = @_;
    $ircdata =~ /(.*?) :(.*)/;
    my %h = ( shash => $shash, nick => $nick, target => $1, text => $2, host => $mask );

    return if(
        $shash->ignore_check($nick, $mask, $h{target},$h{text}, MSGLEVEL_PUBLIC) ||
        $h{text} !~ /${t}\w/
    );

    $h{server} = $shash->{tag};
    my $channel = $shash->channel_find( $h{target} );
    if ( $shash->ischannel( $h{target} ) ) {
        return if( $fp{"$h{target}$h{server}"} > time );
        if( $h{text} !~ /^(.\w+)2( .*|$)/ ) {
            $h{scorebot} = 1 if( $channel->nick_find_mask( 'scores!*johne@*' ) );
            $h{goalbot} = 1 if( $channel->nick_find_mask( 'GoalBot!*johne@*' ) );
        } else {
            $_ = "$1$2";
            $h{text} = $_ if( $h{text} !~ /${t}(stats|last|next)/i );
        }
    } else {
        return if( $fp{"priv$h{server}"} > time );
        $fp{"priv$h{server}"} = time + 3;
        $h{target} = $nick;
    }
    event_privmsg( \%h );
}

sub event_privmsg {
    my $params = shift;
    my %h = %$params;
    my $noticereply;
    my @ret;
    my( $target, $text, $scorebot, $goalbot ) = ( $h{target}, $h{text}, $h{scorebot}, $h{goalbot} );
    #$t = $target =~ /#hockey/i ? qr/!/ : qr/\./;
    return if( $text !~ $t );

    $_ = lc( $text );

    if( /${t}stats (\w+.*)/ ) {
        @ret = StatsNHL( $1 ); }
    elsif( /${t}pstats (\w+.*)/ ) {
        @ret = StatsNHL( $1, 1 ); }
    elsif( /${t}(?:stats2|oldstats|statsold) (\w+.*)/ ) {
        @ret = StatsHDB( $1 );
    }
    elsif( /${t}(.*?)standings(.*)/ ) {
        if( !$1 ) {
            my $param = $2;
            foreach( lc( $target ) ) {
                if( /nhl|hockey/ ) { $text = ".nhlstandings$param" }
                if( /^\#bluejays/ ) { $text = ".mlbstandings$param" }
            }
        } elsif( $1 eq 'mlb' && lc( $target ) eq '#nhl' ) {
            $noticereply = 1;
        }
        @ret = Standings( substr( $text, 1 ) ) unless $scorebot; }
    elsif( /${t}gstats ?(.*)/ ) {
        @ret = StatsGame( $1 ); }
    elsif( /${t}tstats (\w+.*)/ ) {
        @ret = StatsTeam( $1 ); }
    elsif( /${t}nhlleaders? ?(.*)/ ) {
        @ret = LeadersNHL( $1 ); } #unless $scorebot; }
    elsif( /${t}leaders? ?(.*)/ ) {
        my $tmp = $1;
        @ret = LeadersNHL( $tmp ) if( $target =~ /nhl|hockey/ ); }
    elsif( /${t}playoffs?(?: +|$)(.*)/ ) {
        @ret = PlayoffMatches( $1 ) #unless $scorebot;
    }
    elsif( /${t}odds ?(.*)/ ) {
        @ret = BettingOdds( $1 ) unless $scorebot; }
    elsif( /${t}daily ?(.*)/ ) {
        @ret = Daily( $1 ); }
    elsif( /${t}eklund/ ) {
        @ret = Eklund(); # unless $scorebot; }
        }
    elsif( /${t}(?:cap|salary|contract) ([^ ]+.*)/ ) {
        @ret = Salary( $1 ); }
    #elsif( /${t}nhlscii (\w+)/ ) {
        #@ret = getASCII( "http://www.hockeydrunk.com/ascii/$1.txt" ) if( lc( $h{nick} ) eq owner ); }
    elsif( /${t}goalies? ?(.*)/ ) {
        @ret = GoalieStart( $1 ); }
    elsif( /${t}goalhq ra?nd ?($|\d+)/ ) {
        @ret = GoalRND( $1, 1 ); }
    elsif( /${t}goal ra?nd ?($|\d+)/ ) {
        @ret = GoalRND( $1, 0 ); }
    elsif( /${t}goal(?:hq)? ?(.*)/ ) {
        my $params = $1;
        my $hq = /goalhq/;
        @ret = GoalVid( $params, $hq );
        if( $ret[0] =~ /^!!display it (...) (\d+)/ ) {
            $h{goal_team} = $1;
            $h{goal_index} = $2;
            $h{goal_hq} = $hq;
            @ret = GoalQueue( \%h );
        }
        if( $#ret > 0 ) {
            $noticereply = 1;
        }
    }
    elsif( /${t}queuetest (...) (\d+)/ ) {
        $h{goal_team} = $1;
        $h{goal_index} = $2;
        $h{goal_hq} = 0;
        @ret = GoalQueue( \%h );
    }
    elsif( /${t}nascar/ ) {
        @ret = 'Turning left.' unless $scorebot; }
    elsif( /${t}pick (\w+ \w+.*)/ ) {
        if( !$scorebot ) {
            my @picks = split( ' ', $1 );
            @ret = "Roll of the dice picks " . $picks[ rand( $#picks + 1 ) ];
        }
    }
    elsif( /${t}gcl ?(.*)/ ) {
        #@ret = GCL( $1 ); b0rk
        $noticereply = 1;
    }
    elsif( /${t}summary ?(.*)/ ) {
        @ret = Summary( $1 ); }
    elsif( /${t}nhlnews (\w.*)/ ) {
        @ret = RotoNews( $1 ); }
    elsif( /${t}sched(?:ule)? ?(.*)/ ) {
        if( $target =~ /olym/i ) {
            @ret = OlympicsSched( $1 );
        } else {
            @ret = SchedNHL( $1 );
        }
    }
    elsif( /${t}rookies ?(\d+)?/ ) {
        my $i = ( $1 > 5 || $1 < 1 ) ? 5 : $1;
        @ret = Rookies( $i );
    }
    elsif( /${t}wildcard ?(\w*)/ ) {
        @ret = Wildcard( $1 ); }
    elsif( /${t}xrxs (\w+)/ ) {
        @ret = xrxs( $1 ); }
    elsif( /${t}osched ?(.*)/ ) {
        @ret = OlympicsSched( $1 ); }
    elsif( /${t}o?medals ?(.*)/ ) {
        @ret = OlympicsMedals( $1 ) unless $scorebot; }
    elsif( /${t}(next|last)(?:game)?(\d| |$)/ ) {
        my($t) = $text =~ / (.*)/ ? $1 : '';
        my($season) = $t =~ /(20\d\d)$/ ? " $1" : "";
        $text =~ s/20\d\d$// if( $season );
        my($num) = $text =~ /(\d+)/ ? $1 : 1;
        $t =~ s/\d+//g;
        if( !$t ) {
            @ret = 'Usage: ' . lc substr($text,1,4) . ' <team> [<team2>] [<count>] [<season>]';
        } else {
            @ret = SchedNHL( "$t " . ($text =~ /last/i ? -$num : $num) . $season );
        }
        
    }
    elsif( /${t}hls/ ) {
        @ret = 'Get an HLS player for your browser like this one: https://chrome.google.com/webstore/detail/native-hls-playback/emnphkkblegpebimobpbekeedfgemhof?hl=en-US or https://addons.mozilla.org/en-US/firefox/addon/native_hls_playback/'; }
    elsif( /${t}help$/ ) {
        @ret = 'http://192.95.27.97/haaalp.txt';
    }
    elsif( /${t}ragewings$/ ) {
        return; # if( (lc($target) !~ /#(nhl|hockey|pens)/) || ($fp{"rw$server"} > time) || ($scorebot == 1) );
        $fp{"rw$server"} = time + 30;
        @ret = getRW( );
    }
    elsif( /${t}test$/ ) {
        if( lc( $h{nick} ) eq owner ) {
            @ret = "Cache hits: $httpcache{hits}";
        }
    }
    elsif( $target =~ /^#nhl$/i && $text =~ /${t}n[hf]l/i && $scorebot == 0 && $goalbot == 1 ) {
        return;
    }
    elsif( /${t}ohl ?(.*)/ ) {
        @ret = OHL( $1 ); }
    elsif( /${t}(?:chl|mem) ?(.*)/ ) {
        @ret = CHL( $1 ); }
    elsif( /${t}(?:nhl|nfl|nba|mlb|mls|wj|whc|iihf)/i ) {
        @ret = Scores( substr( $text, 1 ) ) if( !$scorebot );
        foreach( @ret ) { BoldScore( $_ ); }
    }

    return if( !@ret );
    if( $fp{"$target$h{server}"} >= time ) {
        $fp{"$target$h{server}"} = time + 2;
    } else {
        $fp{"$target$h{server}"} = time;
    }

    if( lc $h{server} eq 'quakenet' ) {
        $noticereply = 1 if( $#ret > 1 && $target eq '#nhl.fi' );
        #finnish time zone
        foreach( @ret ) {
            s/\x02//g if( !$noticereply );
            #TZ=Europe/Helsinki date --date='TZ="America/Toronto" 07:00' '+%R GMT%-:z'
            #14:00 GMT+2:00
            if( /(... ... \d+, \d{4}.*?[AP]M)/ ) {
                my $d = $1;
                my( $local ) = `TZ=Europe/Helsinki date --date='TZ="America/Toronto" $d' '+%a %b %-d, %Y %-H:%M GMT%-:z' 2>&1` =~ /(.*)/;
                ($local) =~ s/(GMT\+\d):\d\d/$1/
                    and s/\Q$d\E/$local/;
            } elsif( /(\d+:\d{2}(?: ?[AP]M)?(?: ?E[SD]?T)|\d+:\d{2} [ap]\.m\. ET)/i ) {
                my( $t, $t2 ) = ( $1, $1 );
                $t2 =~ s/ ?E[SD]?T//;
                $t2 .= 'pm' if( $t2 !~ /m\.?$/i );
                my( $local ) = `TZ=Europe/Helsinki date --date='TZ="America/Toronto" $t2' '+%-H:%M GMT%-:z' 2>&1` =~ /(.*)/;
                ($local) =~ s/(GMT\+\d):\d\d/$1/
                    and s/\Q$t\E/$local/;
            }
        }
    }
    $target = $h{nick} if( $noticereply );

    if( $target =~ /^#(nhl|hockey|ash.*)$/i ) {
        foreach( @ret ) {
            s/ (shar)ks/ \x0310$1ts\x0f/ig;
            s/c(\.|\w+) giroux( +)/Dink Giroux /i;
            if( $2 && length($2) > 1 ) {
                my $spaces;
                if( length($1) == 1 ) {
                    $spaces = substr( $2, 0, length($2) - 3 ) if( length($2) > 3 );
                } else {
                    $spaces = "$2 ";
                }
                s/Dink Giroux/Dink Giroux$spaces/;
            }
        }
    }
    for my $i ( 0 .. $#ret ) {
        next if( !$ret[$i] );
        if( exists &weechat::command ) {
            weechat::command( $h{buffer}, ($noticereply ? "/notice $target " : "") . $ret[$i] );
            #weechat::print( $h{buffer}, $ret[$i] );
            sleep ($i < 10 ? $i/10 : 1) if( $i > 3 );
        } else {
            #$h{shash}->send_raw_now( ($noticereply ? "NOTICE" : "PRIVMSG") . " $target :$ret[$i]" );
            #$h{shash}->print($target, $ret[$i], MSGLEVEL_CLIENTCRAP);
            $h{shash}->command( ($noticereply ? "notice" : "msg") . " $target $ret[$i]" );
        }
    }
}

our $hs_api_key;
sub weechat_get_conf_cb {
    $hs_api_key = weechat::config_get_plugin( "hs_api_key" );
    return weechat::WEECHAT_RC_OK;
}

sub irssi_get_conf_cb {
    require Irssi;
    my @stat_settings;
    my $file = Irssi::get_irssi_dir."/stats_conf";
    open FILE, "< $file" or return;

    while (<FILE>) {
        chomp;
        push @stat_settings, $_;
    }

    close FILE;

    $hs_api_key = $stat_settings[0];
    #Irssi::print("stats_conf reloaded from $file $hs_api_key");
}

use constant UA => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.96 Safari/537.36";
sub zget{
    require LWP::UserAgent;
    require HTTP::Message;
    my( $url, $attempt ) = @_;
    my $ua = LWP::UserAgent->new(
        agent => UA,
        timeout => 3 );
    $attempt = $attempt ? $attempt+1 : 1;
    my $response = $ua->get( $url, 'Accept-Encoding' => HTTP::Message::decodable() );
    print "zget: $attempt. $url (" . $response->status_line . ") [" . length( $response->content ) . "]\n" if( DEBUG );
    return $response->decoded_content( charset => 'none' ) if( $response->is_success );
    return zget( $url, $attempt ) if( $attempt < 3 && $response->code != 404 );
    return "";
}

sub wget {
    my( $url, $extra ) = @_;
    my $UA = UA;
    return `LD_PRELOAD='' wget -t 3 -T 3 -q -O - '$url' -U '$UA' $extra 2>/dev/null`;
}
sub curlhead {
    my $url = shift;
    my $UA = UA;
    return `LD_PRELOAD='' curl -A '$UA' -I '$url' 2>/dev/null`;
}

sub lget {
    my $url = shift;
    my $extra = "-http.fake-user-agent '" . UA . "'" . ($httpref ? " -http.fake-referer '$httpref' -http.referer 2" : "");    
    my $data = `LD_PRELOAD='' links -receive-timeout 3 $extra -source -address-preference 3 '$url' 2>/dev/null | gunzip -f 2>/dev/null`;
    $data = "" if( length($data) < 200 && $data =~ /40[0-9]|Not Found/i );
    return $data;
}
sub links {
    $_ = shift;
    return `LD_PRELOAD='' links -width 400 -receive-timeout 3 -dump '$_' 2>/dev/null`;
}

sub GetDate {
    my( $date, $fmt ) = @_;
    $date =~ s/'//g;
    my( $ret ) = `date --date='$date' "+$fmt" 2>&1` =~ /(.*)/;
    return $ret;
}

#globals
our %fp;
our %fl;
our %GD;
our %GQ; #goalqueue

sub FindTeam{
    use constant teams => ( '0 is null',
        'Anaheim Ducks','Boston Bruins','Buffalo Sabres','Calgary Flames','Carolina Hurricanes',
        'Chicago Blackhawks','Colorado Avalanche','Columbus Blue Jackets','Dallas Stars','Detroit Red Wings',
        'Edmonton Oilers','Florida Panthers','Los Angeles Kings','Minnesota Wild','Montreal Canadiens',
        'Nashville Predators','New Jersey Devils','New York Islanders','New York Rangers','Ottawa Senators',
        'Philadelphia Flyers','Arizona Coyotes','Pittsburgh Penguins','St. Louis Blues','San Jose Sharks',
        'Tampa Bay Lightning','Toronto Maple Leafs','Vancouver Canucks','Washington Capitals','Winnipeg Jets',
        'Vegas Golden Knights'
    );
    use constant abv => qw( 0_is_null
        ANA BOS BUF CGY CAR CHI COL CBJ DAL DET EDM FLA LAK MIN MTL
        NSH NJD NYI NYR OTT PHI ARI PIT STL SJS TBL TOR VAN WSH WPG VGK
    );
    my( $search, $forceabv ) = ( uc shift, shift );
    return (teams)[ $search ] if( ($search =~ /^[1-9]+0?$/) && ($search < teams) );
    foreach( $search ) {
        return (abv)[13] if( /^LA$/ );
        return (abv)[15] if( /^(?:HABS|MON)/ );
        return (abv)[17] if( /^NJ$/ );
        return (abv)[18] if( /ISL[AE]/ );
        return (abv)[19] if( /RAN?G/ );
        return (abv)[20] if( /^SENS$/ );
        return (abv)[22] if( /PH[OX]$/ );
        return (abv)[23] if( /PGH|PENS/ );
        return (abv)[24] if( /LOUIS/ && $_ !~ /MART/ );
        return (abv)[25] if( /^SJ$/ );
        return (abv)[26] if( /^(?:TB($|[^L])|BOLTS)/ );
        return (abv)[29] if( /^(?:WAS|CAPS)/ );
        return (abv)[30] if( /^WIN/ );
        return (abv)[31] if( /VEGAS|^LAS|GOL|LV/ );
    }
    for my $i ( 1 .. (teams - 1) ) {
        if( (abv)[$i] eq $search ) {
            return $forceabv ? (abv)[$i] : (teams)[$i];
        }
        return (abv)[$i] if( uc( (teams)[$i] ) eq $search );
    }
    $search =~ s/ //g;
    for my $i ( 1 .. (teams - 1) ) {
        my( $nospace ) = uc( (teams)[$i] );
        $nospace =~ s/ //g;
        return (abv)[$i] if( $nospace =~ /\Q$search\E/ );
    }
    return 0;
} #FindTeam

sub NHLTeamID { #NHL.com team id assignment
    $_ = uc shift;
    if   ( /^ANA$/ ) { return 24 }
    elsif( /^ARI$/ ) { return 53 }
    elsif( /^BOS$/ ) { return  6 }
    elsif( /^BUF$/ ) { return  7 }
    elsif( /^CGY$/ ) { return 20 }
    elsif( /^CAR$/ ) { return 12 }
    elsif( /^CHI$/ ) { return 16 }
    elsif( /^COL$/ ) { return 21 }
    elsif( /^CBJ$/ ) { return 29 }
    elsif( /^DAL$/ ) { return 25 }
    elsif( /^DET$/ ) { return 17 }
    elsif( /^EDM$/ ) { return 22 }
    elsif( /^FLA$/ ) { return 13 }
    elsif( /^LAK$/ ) { return 26 }
    elsif( /^MIN$/ ) { return 30 }
    elsif( /^MTL$/ ) { return  8 }
    elsif( /^NSH$/ ) { return 18 }
    elsif( /^NJD$/ ) { return  1 }
    elsif( /^NYI$/ ) { return  2 }
    elsif( /^NYR$/ ) { return  3 }
    elsif( /^OTT$/ ) { return  9 }
    elsif( /^PHI$/ ) { return  4 }
    elsif( /^PIT$/ ) { return  5 }
    elsif( /^STL$/ ) { return 19 }
    elsif( /^SJS$/ ) { return 28 }
    elsif( /^TBL$/ ) { return 14 }
    elsif( /^TOR$/ ) { return 10 }
    elsif( /^VAN$/ ) { return 23 }
    elsif( /^VGK$/ ) { return 54 }
    elsif( /^WSH$/ ) { return 15 }
    elsif( /^WPG$/ ) { return 52 }
    return 0;
} #NHLTeamID

our %httpcache;
sub download {
    no warnings;
    my( $url, $nocache ) = @_;
    $url =~ s/'/'"'"'/g;
    return lget( $url ) if( $nocache );
    my $t = time;
    for my $c ( 1 .. 5 ) {
        if( $httpcache{$c}{url} && $t >= $httpcache{$c}{timer} ) {
            undef $httpcache{$c}{url};
            undef $httpcache{$c}{data};
            $httpcache{$c}{timer} = 0;
        }
    }
    for my $c ( 1 .. 5 ) {
        if( $httpcache{$c}{url} eq $url ) {
            $httpcache{hits}++;
            $httpcache{$c}{timer} = time + 30;
            return $httpcache{$c}{data};
        }
    }
    my $tmp = lget( $url );
    if( $tmp ) {
        $httpcache{index}++;
        $httpcache{index} = 1 if( $httpcache{index} > 5 );
        $httpcache{$httpcache{index}}{url} = $url;
        $httpcache{$httpcache{index}}{data} = $tmp;
        $httpcache{$httpcache{index}}{timer} = time + 30;
    }
    return $tmp;
}

sub SchedNHL {
    #new sched using statsapi
    #http://statsapi.web.nhl.com/api/v1/schedule?expand=schedule.teams,schedule.linescore,schedule.decisions&teamId=10&gameType=R&season=20162017

    my $params = shift;
    return 'sched <team> [<team2>] [<index>] [<season>]' if( !$params );
    print "SchedNHL: $params~\n" if( DEBUG );

    my $opp = $params =~ /[^ ]+ ([^\d -]+)/ ? $1 : '';
    if( $opp ne '' ) {
        $opp = FindTeam( $opp );
        $opp = FindTeam( $opp ) if( length( $opp ) != 3 );
        return 'opponent not found' if( !$opp );
        $opp = NHLTeamID( $opp );
    }

    my $team = $params =~ /(\w+)/ ? FindTeam( $1 ) : '';
    $team = length( $team ) != 3 ? FindTeam( $team ) : uc( $team );
    return 'team not found' if( !$team );

    my $index = $params =~ /(-?\d+) ?(?:20\d\d)?$/ ? $1 : 1;
    $index = 1 if( !$index );
    $index = 5 if( !DEBUG && $index > 5 );
    $index = -5 if ( !DEBUG && $index < -5 );

    my $season = $params =~ /(20\d\d)$/ ? $1 : GetDate( '8 months ago', "%Y" );
    my $today = $params =~ /20\d\d$/ ? ($season+1) . "-07-01" : GetDate( 'today', "%Y-%m-%d" );
    my $url = "http://statsapi.web.nhl.com/api/v1/schedule?expand=schedule.teams,schedule.linescore" . ($params =~ /20\d\d$/ ? "&gameType=R" : "");
    $url .= "&startDate=" . ($index < 1 ? "$season-10-01&endDate=$today" : "$today&endDate=" . ($season+1) . "-07-01");

    my $nhlid = NHLTeamID( $team );
    my $data = download( "$url&teamId=" . $nhlid );
    my $js;
    eval { $js = decode_json( $data ); };
    return 'nhl.com error' if( $@ );

    my @games = @{$js->{dates}};
    if( $opp ) {
        @games = grep { $_->{games}->[0]->{teams}{away}{team}{id} == $opp || $_->{games}->[0]->{teams}{home}{team}{id} == $opp } @games;
    }

    my @ret;
    if( $index < 1 ) {
        @games = reverse @games;
        foreach( @games ) {
            next if( !$_->{games}->[0]->{linescore}{currentPeriodTimeRemaining} );
            my $game = $_->{games}->[0]->{teams}{away}{team}{abbreviation} . " " . $_->{games}->[0]->{teams}{away}{score}
                ." " . $_->{games}->[0]->{teams}{home}{team}{abbreviation} . " " . $_->{games}->[0]->{teams}{home}{score};
            BoldScore( $game );
            $game .= " ( " . uc $_->{games}->[0]->{linescore}{currentPeriodTimeRemaining};
            $game .= ($_->{games}->[0]->{linescore}{currentPeriod} > 3 ? " $_->{games}->[0]->{linescore}{currentPeriodOrdinal} )" : " )");
            push @ret, $game . GetDate( $_->{date}, ' %b %d %Y' );
            last if @ret == abs( $index );
        }
    } else {
        foreach( @games ) {
            my $game;
            if( $_->{games}->[0]->{teams}{away}{team}{id} == $nhlid ) {
                $game = "at " . $_->{games}->[0]->{teams}{home}{team}{abbreviation}
            } else {
                $game = "vs " . $_->{games}->[0]->{teams}{away}{team}{abbreviation}
            }
            if( $_->{games}->[0]->{status}{statusCode} eq '8' ) {
                push @ret, $game . GetDate( $_->{games}->[0]->{gameDate}, ' %a %d %b %Y (TBD)' );
            } else {
                push @ret, $game . GetDate( $_->{games}->[0]->{gameDate}, ' %c' );
            }
            last if @ret == $index;
        }
    }
    return @ret ? @ret : 'no games found';
}

sub SchedNHLold {

    my $params = shift;
    return 'sched <team> [<team2>] [<index>]' if( !$params );
    print "GetSched: $params~\n" if( DEBUG );

    my $opp = $params =~ /[^ ]+ ([^\d -]+)/ ? $1 : '';
    if( $opp ne '' ) {
        $opp = FindTeam( $opp );
        $opp = FindTeam( $opp ) if( length( $opp ) != 3 );
        return 'opponent not found' if( !$opp );
    }

    my $team = $params =~ /(\w+)/ ? FindTeam( $1 ) : '';
    $team = length( $team ) != 3 ? FindTeam( $team ) : uc( $team );
    return 'team not found' if( !$team );

    my $index = $params =~ /(-?\d+) ?$/ ? $1 : 1;
    $index = 1 if( !$index );
    $index = 5 if( !DEBUG && $index > 5 );
    $index = -5 if ( !DEBUG && $index < -5 );

    my $ymdt = GetDate( '1 hour ago', '%Y%m%d %T' );
    my $season = GetDate( '8 months ago', "%Y" );
    my $data = download( "http://live.nhl.com/GameData/SeasonSchedule-$season" . ($season + 1) . ".json" );
    my $js;
    eval { $js = decode_json( $data ); };
    return 'nhl.com error' if( ! $js );

    my @games = grep { ($_->{a} eq $team || $_->{h} eq $team) && ($opp eq '' || $_->{a} eq $opp || $_->{h} eq $opp) } @$js;
    @games = sort { $a->{est} cmp $b->{est} } @games;
    my @ret;
    if( $index > 0 ) {
        foreach( grep { ( substr( $_->{est}, 0, 17 ) ge $ymdt ) } @games ) {
            push @ret, ($_->{h} eq $team ? "vs $_->{a}" : "at $_->{h}") . GetDate( $_->{est}, ' %c' );
            last if( @ret eq $index );
        }
    } else {
        foreach( grep { ( substr( $_->{est}, 0, 17 ) lt $ymdt ) } reverse( @games ) ) {
            my $est = $_->{est};
            push @ret, ScoresNHL( $_->{id} . " " . GetDate( $est, '%Y%m%d' ) );
            BoldScore( $ret[$#ret] ) if( !DEBUG );
            $ret[$#ret] .= GetDate( $est, ' %b %d %Y' );
            last if( @ret eq abs( $index ) );
        }
        @ret = reverse @ret;
    }
    return @ret ? @ret : 'no games found';
} #SchedNHL

sub CHL {
    my @ret;
    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    $date = GetDate( 'now', '%Y-%m-%d' ) if( !$date );

    my $url = "http://cluster.leaguestat.com/lsconsole/json.php?client_code=chl&forcedate=$date";
    my $data = download( $url );
    my $GameStatus;

    ( $data ) = ( $data =~ /var todayData = '(.*?)'\;/s );
    my ( @games ) = ( $data =~ /Game.*?"\:\{(.*?)\}\}/gs );
    return 'No games found.' if( !@games );
    foreach (@games) {
        my ($ID, $Number, $Letter, $Label, $Date, $Time, $Zone, $Status, $ShortStatus, $SmallStatus, $StatusID, $Clock, $Period, $Away, $AwayCode, $AwayUrl, $AwayScore, $Home, $HomeCode, $HomeUrl, $HomeScore) = ( /"ID"\:"(.*?)".*?Number"\:"(.*?)".*?Letter"\:"(.*?)".*?Label"\:"(.*?)".*?Date"\:"(.*?)".*?ScheduledTime"\:"(.*?)".*?Timezone"\:"(.*?)".*?Status"\:"(.*?)".*?ShortStatus"\:"(.*?)".*?SmallStatus"\:"(.*?)".*?StatusID"\:"(.*?)".*?GameClock"\:"(.*?)".*?"Period"\:"(.*?)".*?Name"\:"(.*?)".*?Code"\:"(.*?)".*?AudioUrl"\:"(.*?)".*?Score"\:"(.*?)".*?Name"\:"(.*?)".*?Code"\:"(.*?)".*?AudioUrl"\:"(.*?)".*?Score"\:"(.*?)"/s );
        $HomeUrl =~ s/\\//g;
        $AwayUrl =~ s/\\//g;
        $HomeUrl =~ s/\&amp\;/\&/g;
        $AwayUrl =~ s/\&amp\;/\&/g;
        if (length($HomeCode) ==4) { $HomeCode = substr($HomeCode, 0, -1); }
        if (length($AwayCode) ==4) { $AwayCode = substr($AwayCode, 0, -1); }
        $AwayCode =~ s/^(?=..$)/ /;
        $HomeCode =~ s/(?<=^..)$/ /;
        if( $search =~ /[^\*]+/ ) {
            next if( "$Away $Home $AwayCode $HomeCode" !~ /\Q$search\E/i );
        }

        if ($Clock == "0:00") { $Clock = "END" }
        if ($Clock == "20:00") { $Clock = "START" }

        if ($StatusID == 1) {
            $GameStatus = "$Time $Zone";
            my $format = "%-3s @ %-3s %-10s";
            push @ret,  sprintf($format, ($AwayCode, $HomeCode, "( $GameStatus )"));
        } elsif ($StatusID == 2) {
            $GameStatus = "$Clock $Period"; $AwayCode = "$AwayCode $AwayScore"; $HomeCode = "$HomeCode $HomeScore";
            my $format = "%-4s %-4s %-10s";
            push @ret,  sprintf($format, ($AwayCode, $HomeCode, "( $GameStatus )"));
            BoldScore( $ret[$#ret] )
        } else {
            $GameStatus = "$SmallStatus"; $AwayCode = "$AwayCode $AwayScore"; $HomeCode = "$HomeCode $HomeScore";
            my $format = "%-4s %-4s %-10s";
            push @ret,  sprintf($format, ($AwayCode, $HomeCode, "( $GameStatus )"));
            BoldScore( $ret[$#ret] )
        }
    }
    return @ret ? @ret : 'no games found';
}

sub OHL {
    my @ret;
    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    $date = GetDate( 'now', '%Y-%m-%d' ) if( !$date );

    my $url = "http://cluster.leaguestat.com/lsconsole/json.php?client_code=ohl&forcedate=$date";
    my $data = download( $url );
    my $GameStatus;

    ( $data ) = ( $data =~ /var todayData = '(.*?)'\;/s );
    my ( @games ) = ( $data =~ /Game.*?"\:\{(.*?)\}\}/gs );
    return 'No games found.' if( !@games );
    foreach (@games) {
        my ($ID, $Number, $Letter, $Label, $Date, $Time, $Zone, $Status, $ShortStatus, $SmallStatus, $StatusID, $Clock, $Period, $Away, $AwayCode, $AwayUrl, $AwayScore, $Home, $HomeCode, $HomeUrl, $HomeScore) = ( /"ID"\:"(.*?)".*?Number"\:"(.*?)".*?Letter"\:"(.*?)".*?Label"\:"(.*?)".*?Date"\:"(.*?)".*?ScheduledTime"\:"(.*?)".*?Timezone"\:"(.*?)".*?Status"\:"(.*?)".*?ShortStatus"\:"(.*?)".*?SmallStatus"\:"(.*?)".*?StatusID"\:"(.*?)".*?GameClock"\:"(.*?)".*?"Period"\:"(.*?)".*?Name"\:"(.*?)".*?Code"\:"(.*?)".*?AudioUrl"\:"(.*?)".*?Score"\:"(.*?)".*?Name"\:"(.*?)".*?Code"\:"(.*?)".*?AudioUrl"\:"(.*?)".*?Score"\:"(.*?)"/s );
        $HomeUrl =~ s/\\//g;
        $AwayUrl =~ s/\\//g;
        $HomeUrl =~ s/\&amp\;/\&/g;
        $AwayUrl =~ s/\&amp\;/\&/g;
        if (length($HomeCode) ==4) { $HomeCode = substr($HomeCode, 0, -1); }
        if (length($AwayCode) ==4) { $AwayCode = substr($AwayCode, 0, -1); }
        $AwayCode =~ s/^(?=..$)/ /;
        $HomeCode =~ s/(?<=^..)$/ /;
        if( $search =~ /[^\*]+/ ) {
            next if( "$Away $Home $AwayCode $HomeCode" !~ /\Q$search\E/i );
        }

        if ($Clock eq "0:00") { $Clock = "END" }
        if ($Clock eq "20:00") { $Clock = "START" }

        if ($StatusID == 1) {
            $GameStatus = "$Time $Zone";
            my $format = "%-3s @ %-3s %-10s";
            push @ret,  sprintf($format, ($AwayCode, $HomeCode, "( $GameStatus )"));
        } elsif ($StatusID == 2) {
            $GameStatus = "$Clock $Period"; $AwayCode = "$AwayCode $AwayScore"; $HomeCode = "$HomeCode $HomeScore";
            my $format = "%-4s %-4s %-10s";
            push @ret,  sprintf($format, ($AwayCode, $HomeCode, "( $GameStatus )"));
            BoldScore( $ret[$#ret] )
        } else {
            $GameStatus = "$SmallStatus"; $AwayCode = "$AwayCode $AwayScore"; $HomeCode = "$HomeCode $HomeScore";
            my $format = "%-4s %-4s %-10s";
            push @ret,  sprintf($format, ($AwayCode, $HomeCode, "( $GameStatus )"));
            BoldScore( $ret[$#ret] )
        }
    }
    return @ret ? @ret : 'no games found';
}

sub RotoNews {

    my( $data );
    my $search = shift;
    my %g = google( 'http://www.rotowire.com/hockey/', $search );
    for my $c ( 1 .. $g{count} ) {
        #http://www.rotowire.com/hockey/player.htm?id=1675
        if( $g{title}[$c] =~ /\Q$search\E/i && $g{url}[$c] =~ m!(https?://www.rotowire.com/hockey/player\.htm\?[Ii][Dd]=\d+)! ) {
            $data = download( $1, 1 );
            last;
        }
    }
    if( !$data ) {
        $search = "$2,$1" if( $search =~ /(\w+) (.*)/ );
        $_ = download( "http://www.rotowire.com/search.htm?lastname=$search", 1 );
        if( m!<link rel="canonical" href="http://www.rotowire.com/hockey/player\.htm!s ) {
            $data = $_;
        } elsif( /NHL<\/div>.*?<a href="(.*?)"/s ) {
            $data = download( "http://www.rotowire.com$1", 1 );
        }
    }
    return "player not found" if( !$data );
    my( $player ) = $data =~ /<h1>(.*?)</s;
    my( $latest ) = $data =~ /"splayer-namedate">(.*?) .*?<p class="splayer-note".*?>(.*?)<\/p/s ? "\002$1\002: $2" : '';
    $latest =~ s/&nbsp;/ /g;
    my @ret = $latest;

    #map /(fg\d)/g, $str =~ /flag1(.*?)flag2/;
    while( $data =~ /news-item-date">(.*?)<.*?news-item-news.*?>(.*?)<\/div/sg && $#ret < 2 ) {
        push @ret, "\002$1\002: $2";
    }
    foreach( @ret ) { s/<.*?>//sg; }
    $ret[$#ret] = "News for $player - $ret[$#ret]";
    return reverse @ret;
} #rotonews

sub USHL {
    my $search = shift;

    return 'FULLCLIP = UNITED STATES HOCKEY LEAGUE HARDLINER!!!' if( $search =~ /^fullclip$/i );

    my( $data ) = download( 'http://www.ushl.com/index.php?item_id=2443' ) =~ /<h3 c(.*)/s;
    my( @players ) = $data =~ /<tr class="[^>]+>(.*?)<\/tr/sg;
    my( $rPlayer, $rSearch ) = ( qr /<td>\W*(.*?)<\/td>/s , qr /\Q$search\E/i );
    foreach( @players ) {
        my( $p ) = /$rPlayer/;
        return uc( $p ) . " = USHL PRODUCT!!!" if( $p =~ $rSearch );
    }
    return "n";
}

our $playoffcount = 0;
sub PlayoffOdds{
    my $team = FindTeam( shift );
    my $teamabv;
    if( length( $team ) == 3 ) {
        $teamabv = $team;
        $team = FindTeam( $team );
    } else {
        $teamabv = FindTeam( $team );
    }
    my $url = 'http://www.sportsclubstats.com/NHL.html';
    $_ = download( $url );
    return 'ERROR' if( !$_ );
    foreach( /<tr class="team(?:"| odd)(.*?)<\/tr/sg ) {
        my( $name ) = /<a href[^>]+>(.*?)</s;
        if( FindTeam( $name ) eq $teamabv ) {
            my( @td ) = /(<td(?:\/>|[^>]*>.*?<\/td>))/sg;
            foreach( @td ) { s/<.*?>//g; }
            my( $last ) = "$td[1] $td[2]";
            my( $odds ) = />(In|Out)</s;
            if( !$odds ) {
                ($odds) = /class="jt180"[^>]+?title="([^"]+)/s;
            } else {
                unshift @td, '';
            }
            $last = "Did not play" if( length( $last ) < 6 );
            $_ = "$team | Last: $last |\x02 $odds\x02 ($td[13]) | Presidents Trophy $td[17]% ($td[19]) | Stanley Cup $td[14]% ($td[16])";
            $playoffcount++;
            if( $playoffcount >= 5 ) { $_ .= " | $url"; $playoffcount = 0; }
            return $_ ;
        }
    }
    return 'error team not found';
} #playoffodds

sub PlayoffMatches {
    my $params = shift;
    my $search = FindTeam( $1, 1 ) if( $params =~ /(\w+)/ );
    my $season = $params =~ /(\d{4})/ ? "&season=$1" . ($1 + 1) : "";
    my $dateint = int `date +"%m%d"`;
    return PlayoffOdds( $search ) if( (length( $search ) > 0) && (($dateint < 409) || ($dateint > 1000)) );
    
    my $data = download( "http://statsapi.web.nhl.com/api/v1/tournaments/playoffs?expand=round.series$season" );
    my( @ret, $js );
    eval { $js = decode_json( $data ) };
    return "an error occured $1" if( $@ || ($js->{message} && $js->{message} =~ /^(No.*)/) );

    my @rounds = @{ $js->{rounds} };
    for( my $i = ($params =~ /r\S*d ?(\d)/ ? $1 : $js->{defaultRound}) - 1; $i >= 0; $i-- ) {
        @ret = $rounds[$i]->{names}{name};
        foreach( @{ $rounds[$i]->{series} } ) {
            if( $search && $_->{names}{matchupShortName} =~ /$search/ ) {
                my $tmp = "$ret[0] | $_->{names}{matchupName} | $_->{currentGame}{seriesSummary}{seriesStatus}";
                $tmp .= " | " . GetDate( $_->{currentGame}{seriesSummary}{gameTime}, '%c' ) if( $_->{currentGame}{seriesSummary}{seriesStatusShort} !~ /wins/i );
                return $tmp;
            } elsif( !$search ) {
                my $tmp = $_->{names}{matchupShortName};
                $tmp .=  " | " . $_->{currentGame}{seriesSummary}{seriesStatus} if( $_->{currentGame}{seriesSummary}{seriesStatus} );
                if( $_->{currentGame}{seriesSummary}{seriesStatusShort} !~ /wins/i ) {
                    $tmp .= " | " . GetDate( $_->{currentGame}{seriesSummary}{gameTime}, '%a %-l:%M %p %Z' );
                }
                push @ret, $tmp;
            }
        }
        last if( !$search );
    }
    return @ret > 1 ? @ret : 'team not found';
}

sub SalaryTeamCap{
    my $team = shift;
    my $data = download( 'http://www.capgeek.com/payrolls/' );
    my @teams = $data =~ /<td class="team"><a href[^>]+>(.*?)<\/tr>/sg;
    my @topcolumn = $data =~ /<th .*?>(.*?)</sg;

    my $i = 0;
    my @ret;
    $team = FindTeam( $team ) if( $team !~ / / );
    print "SalaryTeamCap: $team | http got $#teams results\n" if( DEBUG );
    foreach( @teams ) {
        my( $t ) = /(.*?)</;
        $t =~ s/[^a-z]+$//;
        $t = FindTeam( FindTeam( $t ) );
        if( $t eq $team ) {
            my( @column ) = /<td align.*?>(?:<span.*?>)?(\$?.*?)</sg;
            if( 0 or !$team ) { #disabled all teams
                #$space =~ s/,//g;
                #$space = pformat( $space, '%.1f' );
                #$ret[$i] .= !$ret[$i] ? "\x02Cap Space:\x02 $t: \$$space" : " | $t \$$space";
                $i++ if( length( $ret[$i] ) > 420 );
            } else {
                $t =~ s/[^a-z]+$//;
                $ret[0] = $t;
                for( $i = 1; $i <= $#topcolumn; $i++ ) {
                    $column[$i-1] = "-" if( !$column[$i-1] );
                    $ret[0] .= " | $topcolumn[$i]\x02 $column[$i-1]\x02";
                }
                $ret[0] =~ s/[\r\n\t]//sg;
                last;
            }
        }
    }
    return @ret;
} #SalaryTeamCap

sub LatestDeals{
    my $num = int( shift );
    my $url = 'http://capgeek.com/latest_contracts.php?listing_type=latest&contract_limit=';
    $url .= $num > 0 && $num <=15 ? $num : '5';

    my $data = download( $url );
    return 'an error occured' if( !$data );

    my @cats = $data =~ /th align.*?>(.*?)<\/th>/sg;
    my @players = $data =~ /<td class="player">(.*?)<\/tr>/sg;
    my( @ret, $max );

    foreach( @players ) {
        my( $detail ) = "[$1]" if( /class="detail">\R?\s*(.*?)\s*<\/td>/s );
        my( $name ) = ( /player\/[0-9]+">(.*?)</s );
        my @items = /td align=.*?>(.*?)<\/td>/sg;
        unshift @items, $name;
        foreach( @items, $detail ) {
            s/(<.*?>)|\R|[»]//sg;
        }
        my %tmp;
        for my $i ( 0 .. $#items ) {
            $tmp{$cats[$i]} = $items[$i];
        }
        $_ = $tmp{'Cap Hit'};
        s/[\d.]+\$//; s/,//g;
        if( /[\d,]+\$[\d,]+/ ) {
            $_ = pformat( $2, '%.1f' )
                . " (Bonus:"
                . pformat( $1, '%.1f' )
                . ")" if( /([\d,]+)\$([\d,]+)/ );
        } else {
            $_ = pformat( $_, '%.1f' );
        }
        push @ret, "$tmp{'Name'} | $tmp{'Pos'} | $tmp{'Team'} | $tmp{'Yrs'} yr | Cap Hit: $_ $detail";
        $ret[$#ret] =~ s/(\s\s+)|(\[\])/ /g;
        $max = length( $1 ) if( $ret[$#ret] =~ /(.*?)\|/ && length( $1 ) > $max );
    }
    foreach( @ret ) {
        my( $tmp ) = /(.*?)\|/;
        while( length( $tmp ) < $max ) { $tmp .= ' '; }
        s/^.*?\|/$tmp\|/;
    }
    return @ret;
} #LatestDeals

sub Salary{

    my $search = lc( shift );
    return LatestDeals( $1 ) if( $search =~ /latest ?(\d+)?/ );
    return SalaryTeamCap( '' ) if( $search eq '*' );
    my $team = FindTeam( $search );
    if( $team ) {
        $team = uc( $search ) if( length( $team ) > 3 );
        return SalaryTeamCap( FindTeam( $team ) );
    }
    # https://www.capfriendly.com/players/alex_ovechkin

    my $data = download( "http://www.capfriendly.com/search?s=$search", 1 );
    if( $data =~ /Results: (\d+)/s ) {
        my $url;
        if( $1 eq 0 ) {
            my %google = google( 'capfriendly.com/players/', $search );
            for my $c ( 1 .. $google{count} ) {
                if( $google{url}[$c] =~ m!players/(.*)! ) {
                    $url = "http://www.capfriendly.com/players/$1";
                    last;
                }
            }
        } else {
            my $top = 0;;
            #print "data: $data\n";
            foreach( $data =~ /<td colspan="\d+"><a href="\/players\/(.*?<\/tr)/sg ) {
                my( $name, $salary ) = /(.*?)".*?(\$.*?<|<\/tr)/s;
                $salary =~ s/[^0-9]//g;
                if( $salary gt $top ) {
                    $top = $salary;
                    $url = "http://www.capfriendly.com/players/$name";
                    last;
                }
            }
        }
        return 'error finding player' if( !$url );
        $data = download( $url, 1 );
    } #else direct link

    #find expiry
    my( $expdata ) = $data =~ /CURRENT.*?<\/h4>(.*?)<\/tbody>/g;
    my @expiry = ( $expdata =~ /<td align="left".*?>(.*?)<\/td>/gs);

    my( $ret ) = $data =~ /CURRENT.*?<\/h4>(.*?)<table/s ? $1 : ' is unsigned';
    $ret =~ s/source:.*?</</si;
    $ret =~ s/<.*?>/\|/g;
    $ret = "$1$ret" if( $data =~ /<h1.*?>(.*?)</s );
    $ret =~ s/ ?\|\|+/ \| /g;
    $ret =~ s/([\w']+)/\u\L$1/g;
    if( $ret =~ /(\d+) Year.*?\$([0-9,]+)/i ) {
        my( $len, $value ) = ( $1, $2 );
        $value =~ s/[^0-9]//g;
        my $hit = pformat( int( $value / $len ), '%.1f' );
        $value = pformat( $value, '%.1f' );
        $ret =~ s/\$.*? /\$$value /;
        $ret .= "Cap Hit: \$$hit";
        $ret .= " | Expiry After $expiry[-1] Season";
    }
#remove the compare line.
    ($ret) =~ s/Compare This Contract \| //s;
    ($ret) =~ s/C.H.% \|/C.H.%/s;
    return $ret;

} #Salary

our %goaliecache;
sub GoalieStart{

    my( $search, $date ) = SplitDate( shift, '%m-%d-%Y'  );
    #$date = GetDate( '-3 hours', '%m-%d-%Y' ) if( !$date );
    my $url = "https://www.dailyfaceoff.com/starting-goalies/$date";

    $search = FindTeam( $search ) if( length( $search ) > 1 );
    $search = FindTeam( $search ) if( length( $search ) == 3 );
    return 'usage: goalie <team> [date]' if( !$search );
    print "Goalie( search: $search )\n" if( DEBUG );

    my $data;
    if( $goaliecache{url} ne $url || time > $goaliecache{timer} ) {
        my $tmp = wget( $url );
        if( $tmp ) {
            $data = $tmp;
            $goaliecache{data} = $tmp;
            $goaliecache{timer} = time + 300;
        }
    } else {
        $data = $goaliecache{data};
    }
    return "error getting data, website down? $url" if( !$data );
    my @games = $data =~ /<div class="stat-card-main-heading"(.*?)(?:"starting-goalies-card stat-card"|$)/sg;
    my @ret;

    foreach( @games ) {
        my @team = /"top-heading-heavy">(.*?) at (.*?)</s;
        my $home = $2 eq $search ? 1 : 0;
        next if( "$1 $2" !~ /\Q$search\E/i );
        my @name = /class="goalie-info.*?<h4>(.*?)</sg;
        my @status = /h5 class="news-strength.*?(\w+)\s*<\/h5>/sg;
        my( $time ) = /game-time">\s*(\d+.*?)\s\s/s;
        push @ret, "$name[$home] is $status[$home] (" . FindTeam($team[0],1) . " @ " . FindTeam($team[1],1) . ", $time)";
    }

    %goaliecache = () if( ! @ret ); #lets clear the cache, this site has problems...        
    return @ret ? @ret : 'No game found';

} #GoalieStart

sub Eklund{

    my $r = int( rand(31) ) + 1;
    my $team = FindTeam( $r );
    print "Eklund r:$r team: $team\n" if( DEBUG );
    my $teamabv;
    if   ( $r == 13 ) { $teamabv = 'LA' }
    elsif( $r == 25 ) { $teamabv = 'SJ' } #stupid espn...
    elsif( $r == 26 ) { $teamabv = 'TB' }
    elsif( $r == 31 ) { $teamabv = 'VGS'}
    else              { $teamabv = FindTeam( $team, 1 ) }

    my $data = download( "http://espn.go.com/nhl/teams/roster?team=$teamabv" );
    my( @players ) = $data =~ /class="...n?row player.*?a href.*?>(.*?)</sg or return 'error';
    my( $player ) = $players[ int( rand( $#players + 1 ) ) ];
    my( @teams, $i );

    for( $i = 0; $i < 3; ) {
        my $t = int( rand( 31 ) ) + 1;
        if(
            ( $t ne $r ) &&
            ( $i < 1 || $teams[0] ne $t ) &&
            ( $i < 2 || $teams[1] ne $t )
        ) {
            $teams[$i] = $t;
            $i++;
        }
    }

    $r = int( rand( 100 ) );
    if   ( $r < 25 ) { $i = 1 }
    elsif( $r < 50 ) { $i = 2 }
    elsif( $r < 75 ) { $i = 3 }
    elsif( $r < 90 ) { $i = 4 }
    else             { $i = 5 }

    foreach( @teams ) { $_ = FindTeam( $_ ); }
    return "$player to the $teams[0], $teams[1] or $teams[2] (e$i)";

} #Eklund

sub Daily{
    my $date = lc( shift );
    my $url = 'http://espn.go.com/nhl/stats/dailyleaders';
    my @ret;

    if( $date ) {
        $date = GetDate( $date, "%Y%m%d" );
        $url .= "/_/date/$date" if( $date !~ /invalid/ );
    }

    my $data = download( $url );
    my @players = ( $data =~ /<tr class=".*?row player.*?><td>(.*?)<\/tr>/sg );
    my $rank = 1;
    my $c = 0;

    #print "$url\n";
    return 'an error occured.' if( @players <=4 );
    push @ret, "TOP 5 Daily Leaders";
    foreach( @players ) {
        s/  +/ /sg;
        my($name,$team,$opp,$score,$wl,$stats) = (
            /href=.*?>(.*?)<.*?<td>(.*?)<.*?<td>(.*?)<.*?href=.*?>(.*?)<.*?span.*?>(.).*?<td>(.*?)</s
        );

        if( ($stats !~ /SV/) || (5 - $rank + $c == 20) ) {
            push @ret, "$rank. $name $stats ($wl $team $opp $score)";
            last if( $rank == 5 );
            $rank++;
        }
        $c++;
    }

    return @ret;
} #daily

sub StatsTeam{

    my $search = shift;
    my $season = $search =~ /(\d{4})/ ? $1 + 1 : GetDate( 'now + 3 months', '%Y' );
    $search =~ s/\s|\d//g;
    $search = FindTeam( $search, 1 );
    return 'tstats <team> [season]' if( length($search) != 3 );
    $search = 'VEG' if( $search eq 'VGK' ); #dumbasses

    print "Looking up team: $search season: " . ($season-1) . "-$season\n" if( DEBUG );
    my $data = download( "http://www.hockey-reference.com/leagues/NHL_$season.html" );

    my ($table) = ( $data =~ /<h2>Team\sStatistics<\/h2>(.*?)<\/table>/s );
    my (@rows) = ($table =~ /<tr.*?>(.*?)<\/tr>/gs );
    shift @rows; shift @rows;

    foreach (@rows) {
        my ($Team, $AvAge, $GP, $W, $L, $OTL, $PTS, $PTSPER, $GF, $GA, $SOW, $SOL, $SRS, $SOS, $TGG, $PP, $PPO, $PPPER, $PPA, $PPOA, $PK, $SH, $SHA, $PIMPER, $OPIMPER, $S, $SPER, $SA, $SVPER, $PDO) = ( /<td.*?>(.*?)<\/td>/gs );
        my ($Code, $Team2) = ( $Team =~ m!<a href="/teams/(.*?)/\d{4}\.html">(.*?)</a>!s );
        if ( $Code =~ /$search/i ) {
            return "$Team2 | Avg. Age $AvAge | GP $GP | W $W | L $L | OTL $OTL | PTS $PTS | PTS% $PTSPER | GF $GF | GA $GA | SOW $SOW | SOL $SOL | SRS $SRS | SOS $SOS | TG/G $TGG | PP $PP | PPO $PPO | PP% $PPPER | PPA $PPA | PPOA $PPOA | PK% $PK | SH $SH | SHA $SHA | PIM/G $PIMPER | OPIM/G $OPIMPER | SHOTS $S | S% $SPER | SA $SA | SV% $SVPER | PDO $PDO";
        }
    }
    return 'an error occured';
}

sub LeadersNHL {

    my $cat = lc( shift );
    my $i = 0;
    my @cats = qw!    p($|[^l]) g($|o)  a       plus|\+   ga  s[av]          w    s[oh]!;
    my @catnames = qw(points    goals   assists plusMinus gaa savePercentage wins shutout);
    foreach( @cats ) {
        last if( $cat =~ /^$_/ );
        $i++;
    }
    
    if( $i == @cats ) {
        return "Valid categories: \x035P\x03oints \x035G\x03oals \x035A\x03ssists " .
            "\x035+\x03/- \x035GAA\x03 \x035SV\x03% \x035W\x03ins \x035Sh\x03utouts";
    }

    my $data = download( 'http://www.nhl.com/stats/rest/leaders' ); # new json rest api
    my $js;
    eval '$js = decode_json( $data )';
    return 'nhl.com error' if( $@ );
    
    foreach( @{ $i < 4 ? $js->{skater} : $js->{goalie} } ) {
        if( $_->{measure} eq $catnames[$i] ) {
            $js = $_;
            last;
        }
    }
    
    print "usin cat $js->{measure}\n" if( DEBUG );
    
    my @ret = "Top 5 " . uc $catnames[$i];
    my @sorted = sort { $a->{listIndex} gt $b->{listIndex } } @{ $js->{leaders} };
    
    my( $maxlen, @players ) = 0;
    for my $c ( 0 .. 4 ) {
        $players[$c] = $sorted[$c]->{'fullName'};
        $players[$c] =~ s/(.).*? /$1\. /;
        $maxlen = length( $players[$c] ) if( length( $players[$c] ) > $maxlen );
    }
    
    for my $j ( 0 .. 4 ) {
        push @ret, sprintf "%d. %-${maxlen}s [%s] \x02%s\x02",
            $j + 1, $players[$j], $sorted[$j]->{'tricode'}, $sorted[$j]->{'valueLabel'};
    }

    return ($#ret == 5 ? @ret : "error occured");

}
    

sub LeadersNHLold {
    my $cat = lc( shift );
    my $i = 0;
    my @cats = qw!    p($|[^l]) g($|o)  a       plus|\+   ga  s[av]          w    s[oh]!;
    my @catnames = qw(points    goals   assists plusMinus gaa savePercentage wins shutout);
    foreach( @cats ) {
        last if( $cat =~ /^$_/ );
        $i++;
    }

    if( $i == @cats ) {
        return "Valid categories: \x035P\x03oints \x035G\x03oals \x035A\x03ssists " .
            "\x035+\x03/- \x035GAA\x03 \x035SV\x03% \x035W\x03ins \x035Sh\x03utouts";
    }

    my( $data, $gdata ) = download( 'www.nhl.com/stats/leaders' ) =~ /LeaderData = (.*?\})\;.*?(\{.*?\})\;/s
        or return 'error occured';

    eval {
        my $js = decode_json( $i > 3 ? $gdata : $data );
        $cat = $js->{$catnames[$i]}->{$catnames[$i]};
    };

    my( @players, $maxlen );
    for my $c ( 0 .. 4 ) {
        $players[$c] = (@$cat)[$c]->{'fullName'};
        $players[$c] =~ s/(.).*? /$1\. /;
        $maxlen = length( $players[$c] ) if( length( $players[$c] ) > $maxlen );
    }

    my @ret = "Top 5 " . uc $catnames[$i];
    for my $j ( 0 .. 4 ) {
        push @ret, sprintf "%d. %-${maxlen}s [%s] \x02%s\x02",
            $j + 1, $players[$j], (@$cat)[$j]->{'tricode'}, (@$cat)[$j]->{'value'};
    }

    return ($#ret == 5 ? @ret : "error occured");

} #LeadersNHL

sub getASCII {
    my $url = shift;
    return if( $fl{$url} > time );
    my $data = download( $url, 1 );
    $data =~ s/\\x([0-9A-Fa-f][0-9A-Fa-f])/chr "0x$1"/ge;
    $data =~ s/\\([0-2][0-9][0-9])/chr "$1"/ge;
    my @ret = split( "\n", $data );
    $fl{$url} = time + 3600;
    return @ret;
}

sub FindGameID {
    my( $team, $date ) = ( \$_[0], $_[1] );

    $$team = FindTeam( $$team, 1 );
    my( $ret) = 0;
    if( $date ) {
        $date = GetDate( $date, '%Y-%m-%d' );
        #http://statsapi.web.nhl.com/api/v1/schedule?startDate=2017-09-21&endDate=2017-09-21
        my $data = download( "http://statsapi.web.nhl.com/api/v1/schedule?startDate=$date&endDate=$date&expand=schedule.linescore" );
        my $js;
        eval '$js = decode_json( $data )';
        return $ret if( $@ );
        
        foreach( @{ $js->{dates}->[0]->{games} } ) {
            if( "$_->{teams}{away}{team}{name} $_->{teams}{home}{team}{name}" =~ FindTeam( $$team ) ) {
                $js = $_;
                return( $js->{gamePk}, $js );
            }
        }
        
    } else {
        if( !$GD{scoreboardtime} || (time > $GD{scoreboardtime}) ) {
            return if( GstatsUpdate() == 0 );
        }
        for( my $i = 0; $i < @{$GD{gamelink}} ; $i++ ) {
            next unless( $$team eq $GD{team}[$i][0] || $$team eq $GD{team}[$i][1] );
            if( $GD{gamelink}[$i] =~ /(\d{4})\d{4}\/.S(\d{6})/ ) {
                $ret = "$1$2";
            }
            return($ret);
        }
    }
    return $ret;
}

sub GoalSearch {

    my( $params ) = shift;
    my( $index ) = $params =~ /(\d+)/;
    $params =~ s/\s*$index\s*/ /;
    my( $team, $date ) = SplitDate( $params, '%Y-%m-%d' );
    my( $fullid ) = FindGameID( $team, $date );
    print "GoalVid -- team: $team index: $index date: $date\n" if( DEBUG );
    return 'usage: goal <team> <index> [date]' if( !$team || !$index );

    my( $url, $ret );
    $fullid =~ /^(\d{4})/
        or return "$team did not play on " . GetDate( ($date ? $date : '-12 hours'), '%b %d, %Y' );

    return GoalVidOld( $fullid, $team, $index, $date ) if( $date && (GetDate( $date, "%Y%m%d" ) < 20160201) );
    #https://search-api.svc.nhl.com/svc/search/v1/nhl_ca_en/query/crosby/tag_plays:goal/1/new/video/20160214/20160214
    #                                                            /search/matchin/pg index/sort/type/date sta/date end/
    my $data = zget( "http://search-api.svc.nhl.com/svc/search/v1/nhl_ca_en/query/%22$fullid%22 goal/tag_teamFileCode:$team/1/new/video/" );
    my $js;

    eval {
        $js = decode_json( $data );
    };
    return 'Goal not found' if( $@ );
    my $goals = $js->{docs};
    my @goal;
    foreach( @$goals ) {
        my( $teamcode, $type, $id, $sortid );
        for( my $i = 0; $i < @{$_->{tags}}; $i++ ) {
            $type = $_->{tags}[$i]{value} if( $_->{tags}[$i]{type} eq 'plays' );
            $teamcode = $_->{tags}[$i]{value} if( $_->{tags}[$i]{type} eq 'teamFileCode' );
            $id = $_->{tags}[$i]{value} if( $_->{tags}[$i]{type} eq 'mediaplaybackid' );
            $sortid = $_->{tags}[$i]{value} if( $_->{tags}[$i]{type} eq 'sunsetDate' );
        }
        if( $teamcode eq $team && $type eq 'goal' ) {
            my %h = ( title => $_->{"bigBlurb"} ? $_->{"bigBlurb"} : $_->{"title"}, id => $id, sid => $sortid );
            push @goal, \%h;
        }
    }
    my @sorted = sort { $a->{sid} gt $b->{sid} } @goal;
    $index--;
    return 'Goal not found or not ready yet' if( ! $sorted[$index] );
    $data = zget( "http://nhl.bamcontent.com/nhlCA/id/v1/$sorted[$index]->{id}/details/web-v1.json" );
    my @vids = $data =~ /"url":"([^"]+?\d+k.mp4)"/sg;
    $vids[$#vids] = shorturl( $vids[$#vids] ) if( !DEBUG );
    return "$vids[$#vids] - $sorted[$index]->{title}"; # . ( $data =~ /powerPlayGoal/ ? " [PPG]" : $data =~ /shorthandedGoal/ ? " [SHG]" : "" );
}


sub GoalVidOld {

    my( $fullid, $team, $index, $date ) = @_;
    my( $url, $vidurl, $ret );

    $url = "http://live.nhl.com/GameData/$1" .($1+1). "/$fullid/PlayByPlay.json";
    my( $season, $gameid ) = ("$1$2",int($3)) if( $url =~ /GameData\/..(..)..(..)\/......(\d+)/ );

    $_ = download( $url );
    my %pbp;
    $pbp{"$1t$2"} = $3 while( /"(?|(a)way|(h)ome)team(?|(id)|(n)ame)":(?|"(.*?)"|(\d+))/sg );
    my( @teams ) = ( FindTeam($pbp{atn}), FindTeam($pbp{htn}) );
    my( $teamid ) = ( $teams[0] eq $team ? $pbp{atid} : $pbp{htid} );
    my( $count, %js );
    while( /\{([^\}]+?"type":"Goal".*?)\}/sg ) {
        %js = simplejson( $1 );
        last if( $js{teamid} == $teamid && ++$count == $index );
    }
    return "error goal not found" if( $index != $count );

    $date = GetDate( ($date ? $date : '-12 hours'), '%Y/%m/%d' );
    for( my $ol = 1; $ol < 3 && !$vidurl; $ol++ ) {
        for( my $il = 1; $il < 3 && !$vidurl; $il++ ) {
            $url = "http://e1.cdnak.neulion.com/nhl/vod/$date/$gameid/" . substr( $fullid, 5, 1 )
                . "_${gameid}_" . lc( $teams[0] ) . "_" . lc( $teams[1] ) . "_${season}_" . ($il == 1 ? 'h' : 'a') . "_discrete_"
                . ($teams[1] =~ /LAK|NJD|SJS|TBL/ ? substr( $teams[1], 0, 1 ) . "." . substr( $teams[1], 1, 1 ) : $teams[1])
                . $js{eventid} . "_goal_" . $ol . "_1600.mp4";
            $vidurl = $url if( curlhead($url) =~ /200 OK/ );
        }
    }

    if( !$vidurl ) {
        for my $ha ( 0 .. 1 ) {
            $_ = download( "http://video.nhl.com/videocenter/servlets/playlist?ids=${fullid}-$js{eventid}-" . ($ha == 0 ? "h" : "a") . "&format=json", 1 );
            $vidurl = /publishpoint":"(.+?)"/i ? $1 : "";
            $ret = $1 if( /"name":"((?! Goal on  ).+?)"/i );
            last if( $vidurl );
        }
    }
    return "error video not ready yet" if( !$vidurl );

    if( !$ret ) {
        my @per = qw( 1st 2nd 3rd OT );
        $ret = $js{desc} . " @ $js{time}/" . ( $js{period} < 5 ? $per[$js{period}-1] : $js{period}-3 . "OT" );
    }
    my @oi = ( scalar split(",",$js{aoi}), scalar split(",",$js{hoi}) );
    $ret .= ($oi[0] > $oi[1] ? ($teamid == $pbp{atid} ? " PP" : " SH") : ($teamid == $pbp{htid} ? " PP" : " SH")) if( $oi[0] != $oi[1] );
    $ret .= sprintf( " [%s " . ($teams[0] eq $team ? "\x02%d\x02 %s %d]" : "%d %s \x02%d\x02]"), $teams[0], $js{as}, $teams[1], $js{hs} );
    $vidurl = shorturl( $vidurl ) if( !DEBUG );
    return "$ret $vidurl";
} #GoalVidOld()

sub GoalVid {

    my( $params, $hq ) = @_;
    my( $index ) = $params =~ /(\d+|all(?:$| ))/i;
    $params =~ s/(\s*)$index\s*/$1/;
    my( $team, $date ) = SplitDate( $params, '%Y-%m-%d' );
    my( $fullid, $js ) = FindGameID( $team, $date );
    my $all = $index =~ /all/i;
    print "GoalVid -- team: $team index: $index date: $date\n" if( DEBUG );
    return 'usage: goal <team> <index> [date]' if( !$team || !$index );
    my( $ret );
    $fullid =~ /^(\d{4})/
        or return "error $team did not play on " . GetDate( ($date ? $date : '-12 hours'), '%b %d, %Y' );

    return GoalVidOld( $fullid, $team, $index, $date ) if( $date && (!$all) && (GetDate( $date, "%Y%m%d" ) < 20160201) );

    my $data = download( "http://statsapi.web.nhl.com/api/v1/game/$fullid/content" );
    my( $json, $nhlteamid );
    eval { $json = decode_json( $data ); };
    return 'error decoding json' if( $@ );
    $nhlteamid = NHLTeamID( $team );

    my @goals = grep{ $_->{type} =~ /GOAL/i && $_->{teamId} == $nhlteamid } @{$json->{media}{milestones}{items}};
    
    for( my $i = $#goals; $i >= 0; $i-- ) {
        for my $j ( 0 .. $#goals ) {
            if( $j ne $i && $goals[$i]->{statsEventId} eq $goals[$j]->{statsEventId} ) {
                splice( @goals, $i, 1 );
                last;
            }
        }
    }
    
    @goals = sort{ $a->{timeOffset} <=> $b->{timeOffset} } @goals;
    if( $index > @goals ) {
        my $home = FindTeam( $js->{teams}{home}{team}{name} ) eq $team;
        return "Goal not found" if( $js->{status}{statusCode} >= 5 || ($index > $js->{teams}{$home ? 'home' : 'away'}{score} + 2) );
        return "!!display it $team $index";
    }
    
    my @ret;
    for my $i ( 0 .. $#goals ) {
        
        next if( !$all && $i ne ($index-1) );
        my $goal = $goals[$i];
    
        if( !$all && !$goal->{highlight}{playbacks} ) {
            return "!!display it $team $index";
        }

        my @playbacks = @{$goal->{highlight}{playbacks}};

        if( $hq ) {
            @playbacks = grep { $_->{name} eq 'HTTP_CLOUD_WIRED_60' } @playbacks;
        } else {
            @playbacks = sort { $b->{height} <=> $a->{height} } grep { $_->{height} && ($_->{height} ne 'null') } @playbacks;
        }

        my $url = $playbacks[0]->{url};
        $url = shorturl( $url ) if( !DEBUG );
        if( !$url ) {
            return "error goal not found" if( !$all );
            next;
        }

        my $desc = "$goal->{highlight}{title} $goal->{highlight}{blurb} $goal->{highlight}{description}";
        my $extra = $desc =~ /(PPG|SHG)/i ? " " . uc $1 : "";

        push @ret, "$url | $goal->{description} [$goal->{periodTime}/$goal->{ordinalNum}$extra] $goal->{highlight}{description}";
        
    }

    return @ret ? @ret : "error goal not found";
    
}

sub GoalQueue {
    my $params = shift;
    my %h = %$params;

    foreach( @{ $GQ{check} } ) {
        if( $h{target} eq $_->{target} and $h{goal_team} eq $_->{goal_team} and $h{goal_index} eq $_->{goal_index} ) {
            return 'Goal is already in queue';
        }
    }

    if( !$GQ{hook} ) {
        if( exists &weechat::command ) {
            $GQ{hook} = weechat::hook_timer( 30000, 0, 0, 'GoalCheck', "" );
        } else {
            $GQ{hook} = Irssi::timeout_add( 30000, 'GoalCheck', "" );
        }
    }

    $h{TTL} = time + 30 * 60;
    push @{ $GQ{check} }, \%h;

    return "Goal added to queue, I will let you know when it's ready $h{nick}";

}

sub GoalCheck {

    for( my $i=0; $i <= $#{ $GQ{check} }; $i++ ) {
        my $vid = GoalVid( "$GQ{check}[$i]{goal_team} $GQ{check}[$i]{goal_index}", $GQ{check}[$i]{goal_hq} );
        if( $vid =~ /^!!|error/ ) {
            next if( time < $GQ{check}[$i]{TTL} );
        } else {
            my $msg = "$GQ{check}[$i]{nick}: $vid";
            if( exists &weechat::command ) {
                weechat::command( $GQ{check}[$i]{buffer}, $msg );
            } else {
                $GQ{check}[$i]{shash}->command( "msg $GQ{check}[$i]{target} $msg" );
            }
        }
        splice @{ $GQ{check} }, $i, 1;
        $i--;
    }

    if( ! @{ $GQ{check} } ) {
        #cleanup the timer hook
        if( exists &weechat::command ) {
            weechat::unhook( $GQ{hook} );
        } else {
            Irssi::timeout_remove( $GQ{hook} );
        }
        delete $GQ{hook};
    }

}

sub xrxs {
    my( $team ) = FindTeam( shift );
    $team = FindTeam( $team ) if( length( $team ) != 3 );
    return 'usage: xrxs team name' if( !$team );
    print "xrxs: $team\n" if( DEBUG );
    my $html = download( "http://xrxs.net/nhl" );

    foreach( $html =~ /(\w+ \d+ 20\d+ .*?<br.*?)<hr/sg ) {
        my( $m3u ) = /(game-[^>]+(?:HOME|VISIT|NATIONAL)-5000.m3u8)/;
        next if( $m3u !~ /$team/ );
        my( $game ) = /\| ?(.*?)<br/;
        my @opts = /game-[^>]+(HOME|VISIT|NATIONAL)-/sg;
        sub uniq {
            my %seen;
            grep !$seen{$_}++, @_;
        }
        @opts = uniq( @opts );
        my @bitrates = /game-[^>]+${opts[0]}-(\d+)/sg;
        return $game . " | http://xrxs.net/nhl/" . $m3u . " | options: @opts @bitrates";
    }

    return 'team not found';

}

sub shorturl {
    my $url = shift;
    $_ = wget( 'https://www.googleapis.com/urlshortener/v1/url?key=AIzaSyBzq7JCfoRml_m7hKndjh7_Y6K1o1ANDO0', "--header 'Content-Type: application/json' --post-data='{\"longUrl\": \"$url\"}'" );
    return /"id":\s*"http.*?(goo.*?)"/ ? "http://$1" : $url;
}

sub Summary {
#NYI 1 MTL 4 Final [ATT 21,288] | SOG 18-24 | PP 0-3/06:00 - 1-2/03:20 | PIM 6-8 | HITS 42-31 | Goals: MTL D.WEISE(8) PP (J.PETRY, P.SUBBAN) | NYI           │
#| K.OKPOSO(4) (J.BOYCHUK, J.HALAK) | MTL D.DESHARNAIS(4) (T.FLEISCHMANN, N.BEAULIEU) | MTL B.GALLAGHER(6) (M.PACIORETTY, T.PLEKANEC) | MTL T.PLEKANEC(6) EN   │
#| (B.GALLAGHER, M.PACIORETTY)
    my( $team, $date ) = SplitDate( shift, '%Y-%m-%d' );
    my( $fullid ) = FindGameID( $team, $date );
    print "team: $team date: $date\n" if( DEBUG );
    return 'usage: summary <team> [<date>]' if( !$team );

    $fullid =~ /(\d{4})(\d+)/
        or return 'game not found';

    my $url = "http://www.nhl.com/scores/htmlreports/$1" .($1+1). "/GS$2.HTM";
    my $data = download( $url, 1 );
    return 'game not yet started' if( !$data );
    my( $ginfo ) = $data =~ /<table id="GameInfo"(.*?)<\/table/s;
    my( $att ) = $ginfo =~ />A[st][st][^ ]+ ([0-9,]+)/s;
    my( $progress ) = $ginfo =~ />(.*?)<\/td>\s*<\/tr>\s*$/;
    $progress =~ s/eriod |aining//g;

    my @team = map { FindTeam( $_ ) } $data =~ /class="teamHeading.*?>(.*?)</sg;
    my @scores = $data =~ /40px\;font\-weight\:bold">(\d+)+/sg;
    $_ = "$team[0] $scores[0] $team[1] $scores[1]";
    BoldScore( $_ );
    my @ret = "$_ $progress" . ( $att ? " [ATT $att]" : '' );

    $ret[0] .= " | SOG $4-$2" if( $data =~ /GOALTENDER SUMMARY(.*?TEAM TOTALS.*?)(\d+)(<\/td>\s*<\/tr)(?1)(\d+)(?3)/s );
    if( my @ppdata = $data =~ /Goals-Opp.*?align="left".*?>(.*?)</sg ) {
        $ret[0] .= " | PP $ppdata[0] - $ppdata[1]";
    }

    #http://live.nhl.com/GameData/20132014/2013021012/gc/gcbx.jsonp
    $url =~ s!.*?(\d{4})(\d+)/GS(\d+).*!http://live.nhl.com/GameData/$1$2/$1$3/gc/gcbx.jsonp!;
    $_ = download( $url, 1 );
    $ret[0] .= " | PIM $+{ap}-$+{hp}" if( /(?:.*?"(?:hPIM":(?<hp>\d+)|aPIM":(?<ap>\d+))){2}/ && ($+{ap}+$+{hp}) > 0);
    $ret[0] .= " | HITS $+{ah}-$+{hh}" if( /(?:.*?"(?:hHits":(?<hh>\d+)|aHits":(?<ah>\d+))){2}/ && ($+{ah}+$+{hh}) > 0);

    my( $c, $g ) = (0,0);
    $_ = $data =~ /SCORING SUMMARY(.*?)PENALTY SUMMARY/s ? $1 : '';
    foreach( /<tr class="(?:odd|even)Color">(.*?)<\/tr/sg ) {
        if( />(SO|OT)</ ) {
            my $extra = $1;
            $ret[0] =~ s!Final !Final/$extra !;
        }
        my( @other ) = /<td align="center">([^\s<]+)/sg;
        next if( /Unsuccessful Penalty Shot/ || !$other[3] );
        my $first;
        my( @who ) = map {s/\(.*//s if( $first ); $first=1; $_} /align="left">\d+ (.*?)</sg;

        if( length( $ret[$c] ) > 380 ) {
            $ret[$c] .= " ...";
            $c++;
        } else {
            $g++;
            $ret[$c] .= ($g == 1 ? ' | Goals: ' : ' | ');
        }
        $other[3] =~ s/EV-EN/EN/;
        $ret[$c] .= "\x02$other[4] $who[0]" .
            ( $other[3] ne 'EV' ? " $other[3]" : '' ) . "\x02" .
            ( $#who > 0 ? " ($who[1]" . ( $#who > 1 ? ", $who[2])" : ')' ) : '' );
    }
    return @ret if( $progress !~ /final/i );

    #look for highlights / recap videos
    $data = download( "http://statsapi.web.nhl.com/api/v1/game/$fullid/content" );
    my( $js, $videos );
    eval { $js = decode_json( $data ); };
    return @ret if( $@ );        
    my @vids = reverse grep { $_->{title} =~ /(highlights|recap)$/i } @{ $js->{media}{epg} };
    for my $i ( 0 .. $#vids ) {
        foreach( @{ $vids[$i]->{items} } ) {
            next if( $_->{type} !~ /video/i || ( $#vids > 1 && $vids[$i]->{title} =~ /extended/i ) );
            my @playbacks = sort { $b->{height} <=> $a->{height} } grep { $_->{height} && ($_->{height} ne 'null') } @{ $_->{playbacks} };
            if( @playbacks ) {
                my $url = $playbacks[0]->{url};
                $url = shorturl( $url ) if( !DEBUG );
                $videos .= ( length( $videos ) ? " | " : "" ) . "$vids[$i]->{title}: $url";
                last;
            }
        }
    }
    push @ret, $videos if( $videos );
    return @ret;

} #summary

sub GstatsGetGame {
    my $index = int( shift );
    return if( $GD{eventsum}[$index] && time < $GD{gtimer}[$index] );
    $_ = download( $GD{gamelink}[$index], 1 );
    if( $_ ) {
        ($GD{eventsum}[$index]) = /TEAM SUMMARY(.*)/s or return;
        my( $away, $home ) = ( $GD{eventsum}[$index] =~ /(.*?)homesectionheading(.*)/s );
        @{$GD{aplayers}[$index]} = ( $away =~ /<tr class="[^>]+?Color">(.*?)<\/tr>/sg );
        @{$GD{hplayers}[$index]} = ( $home =~ /<tr class="[^>]+?Color">(.*?)<\/tr>/sg );
        $GD{gtimer}[$index] = time + 60;
    } else {
        $GD{gtimer}[$index] = time + ( $GD{eventsum}[$index] ? 30 : 300 ) ;
    }
}

sub GstatsUpdate {
    ($_) = download( 'http://live.nhl.com/GameData/RegularSeasonScoreboardv3.jsonp', 1 ) =~ /games":\[(.*)/;
    my @games = /\{(.*?)\}/gs or return 0;
    my $lastnight = `TZ='UTC+17' date '+%^A %-m/%-d'`;
    chomp $lastnight;
    %GD = ();
    my $c = 0;
    foreach( @games ) {
        my %js = simplejson( $_ );
        next if( !$js{id} );
        if( $js{ts} =~ /\Q$lastnight\E|TODAY/i || $js{gs} =~ /[2-4]/ ) {
            print "Gstats~added game id:$js{id}\n" if( DEBUG );
            my $years = $1 . ($1+1) if( $js{id} =~ /^(....)(.*)/ );
            $GD{gamelink}[$c] = "http://www.nhl.com/scores/htmlreports/$years/ES$2.HTM";
            $GD{team}[$c][0] = FindTeam( $js{atn} );
            $GD{team}[$c][1] = FindTeam( $js{htn} );
            $c++;
        }
    }
    $GD{scoreboardtime} = time + 3600 * 6;
    return 1;
}

sub GstatsGoalie {
    my( $i, $team, $search ) = @_;
    my $url = $GD{gamelink}[$i];
    $url =~ s/ES/GS/;
    #http://www.nhl.com/scores/htmlreports/20122013/GS020008.HTM
    my $data = download( $url, 1 );
    ($data) = $data =~ /GOALTENDER SUMMARY(.*)/s;
    my @goalies = ( $data =~ />G<\/td>(.*?)<\/tr/sg );
    foreach( @goalies ) {
        my( $name ) = /<td.*?>([^<]+)/s;
        $name =~ s/ +$//g;
        if( $name =~ /\Q$search\E/i ) {
            my( @table ) = /<td.*?>(.*?)</sg;
            $table[$#table] =~ s/&nbsp;/0-0/;
            $table[4] =~ s/&nbsp;/00:00/;
            my( $ga, $shots ) = $table[$#table] =~ /(\d+)-(\d+)/;
            my( $saves ) = ( $shots - $ga );
            my $mins = $1 + $2 / 60 if( $table[4] =~ /(\d+):(\d+)/ );
            my $gaa = ( 60 / $mins ) * $ga if( $mins );
            my $sv = $saves / $shots if( $shots );

            if( $mins ) {
                $gaa = sprintf( "%4.2f", $gaa );
                $sv = sprintf( "%1.3f", $sv );
            } else {
                $gaa = $sv = 'N/A';
            }
            $name =~ s/\(OT\)$/\(L\)/;
            return "$name | $team | SH $shots | SA $saves | SV% $sv | GAA $gaa | TOI $table[4]";
        }
    }
    return "player not found";
} #GoalieGStats

sub StatsGame {

    my @search = split( ' ', shift );
    my $fresh = 0;
#http://statsapi.web.nhl.com/api/v1/game/2015020837/feed/live
    if( !@search ) {
        return 'PN=Number of Penalties PIM=Penalty Minutes TOI=Time On Ice SHF=# of Shifts AVG=Average Time/Shift S=Shots on Goal A/B=Attempts Blocked MS=Missed Shots HT=Hits Given GV=Giveaways TK=Takeaways BS=Blocked Shots FW=Faceoffs Won FL=Faceoffs Lost F%=Faceoff Win Percentage PP=Power Play SH=Short Handed EV=Even Strength OT=Overtime TOT=Total';
    }

    if( !$GD{scoreboardtime} || (time > $GD{scoreboardtime}) ) {
        print "Gstats~updating scoreboard json\n" if( DEBUG );
        return 'error getting games' if( GstatsUpdate() == 0 );
        $fresh = 1;
    }
    return 'no games today' if( !@{$GD{gamelink}} );
    for( my $i = 0; $i < @{$GD{gamelink}} ; $i++ ) {
        GstatsGetGame( $i ) if( !$GD{eventsum}[$i] );
        next if( !$GD{eventsum}[$i] );

        my( $team, $name, $stats );

        for( my $j = 0; $j < @{$GD{aplayers}[$i]}; $j++ ) {
            $name = $1 if( $GD{aplayers}[$i][$j] =~ /<td.*?<td.*?<td[^>]*>([^<]+)/s );
            if( $name =~ /\Q$search[0]\E/si && $name =~ /\Q$search[1]\E/si ) {
                GstatsGetGame( $i ) if( $fresh == 0 );
                $stats = $GD{aplayers}[$i][$j];
                $team = $GD{team}[$i][0];
                last;
            }
        }
        if( !$stats ) {
            for( my $j = 0; $j < @{$GD{hplayers}[$i]}; $j++ ) {
                $name = $1 if( $GD{hplayers}[$i][$j] =~ /<td.*?<td.*?<td[^>]*>([^<]+)/s );
                if( $name =~ /\Q$search[0]\E/si && $name =~ /\Q$search[1]\E/si ) {
                    GstatsGetGame( $i ) if( $fresh == 0 );
                    $stats = $GD{hplayers}[$i][$j];
                    $team = $GD{team}[$i][1];
                    last;
                }
            }
        }

        if( $stats ) {
            return GstatsGoalie( $i, $team, $name ) if( $stats =~ /<td.*?<td[^>]*>G</s );
            my @cats = qw( G A P +/- PN PIM TOT SHF AVG PP SH EV S A/B MS HT GV TK BS FW FL F% );
            my @items = ( $stats =~ /<td[^>]*>([^<]+)</sg );
            my $ret = "$name | $team";
            for( my $j = 3; $j < @items; $j++ ) {
                $items[$j] =~ s/&nbsp;/0/g ;
                $ret .= " | $cats[$j-3] $items[$j]" #if( $items[$j] ne '0' );
            }
            #$ret .= ' | No game stats yet' if( $ret eq $name );
            return $ret;
        }
    }

    return 'player not found';
} #Gstats

sub Wildcard {
    my $conf = shift;
    return 'Usage: wildcard <east or west>' if( $conf !~ /west|east/ );
    my @ret = StandingsNHL( "$conf -p" );
    return @ret > 8 ? splice( @ret, 8 ) : @ret;
}

sub StandingsNHL {
    my $search = lc shift;
    my( $season ) = $search =~ /(\d{4})$/; #&season=20162017
    my $wild = 0;
    if( $search =~ /(atl|met|cen|pac)/ ) {
        $search = $1;
    } elsif( $search =~ /(\S+?) ?-?(?:wc|p|wild)/ ) {
        $search = $1 eq 'west' ? 'cen|pac' : 'atl|met';
        $wild = 1;
    } elsif( $search =~ /(east|west)/ ) {
        $search = $1;
        if ( !$season && GetDate( 'now', '%m' ) =~ /0[34]/ ) {
            $wild = 1;
            $search = $search eq 'west' ? 'cen|pac' : 'atl|met';
        }
    } else {
        return "Valid categories: EAST WEST ATL CEN MET PAC [add -p for wildcard] [season]";
    }

    print "search: $search ($wild)\n" if( DEBUG );
    my $url = 'http://statsapi.web.nhl.com/api/v1/standings?expand=standings.record,standings.team,standings.division,standings.conference,team.schedule.next,team.schedule.previous';
    my $data = download( $url . ($season ? "&season=$season".($season+1) : ""), 1 );
    my $js;
    eval {
        $js = decode_json( $data );
    };
    return 'error getting standings' if( $@ );

    my @divs = @{$js->{records}};
    my( @tosort, @output, @ret );
    foreach( @divs ) {
        if( "$_->{division}{name} $_->{conference}{name}" =~ /$search/i ) {
            push @tosort, @{$_->{teamRecords}};
        }
    }
    if( $search =~ /atl|met|cen|pac/ ) {
        if( $wild ) {
            my @div1 = grep { $_->{team}{division}{id} == $tosort[0]->{team}{division}{id} } @tosort;
            my @div2 = grep { $_->{team}{division}{id} != $tosort[0]->{team}{division}{id} } @tosort;
            @div1 = sort { $a->{divisionRank} <=> $b->{divisionRank} } @div1;
            @div2 = sort { $a->{divisionRank} <=> $b->{divisionRank} } @div2;
            push @output, splice( @div1, 0, 3 );
            push @output, splice( @div2, 0, 3 );
            push @div1, @div2;
            @div1 = sort { $a->{wildCardRank} <=> $b->{wildCardRank} } @div1;
            push @output, @div1;
        } else {
            @output = sort { $a->{divisionRank} <=> $b->{divisionRank} } @tosort;
        }
        $ret[0] = uc $output[0]->{team}{division}{name};
    } else {
        @output = sort { $a->{conferenceRank} <=> $b->{conferenceRank} } @tosort;
        $ret[0] = uc $output[0]->{team}{conference}{name};
    }

    $ret[0] = sprintf( "%-17s GP   W   L  OT  \x02PTS\x02  ROW   GF   GA  DIFF     L10  STRK", $ret[0] );
    foreach( @output ) {
        my( $rank, $lastten );
        my $diff = $_->{goalsScored} - $_->{goalsAgainst};
        my $diffcolors = "\x03" . ($diff < 0 ? "4" : "3") . " %4d\x03";
        $_->{team}{locationName} = ( "NY " . $_->{team}{teamName} ) if( $_->{team}{locationName} eq 'New York' );
        if( $wild ) {
            $rank = $_->{wildCardRank} ? $_->{wildCardRank} : $_->{divisionRank};
        } else {
            $rank = @output < 10 ? $_->{divisionRank} : $_->{conferenceRank};
        }
        foreach( @{$_->{records}{overallRecords}} ) {
            $lastten = "$_->{wins}-$_->{losses}-$_->{ot}" if( $_->{type} eq "lastTen" );
        }
        push @ret, sprintf(
            #rk  tm    gp   w   l  ot      pts     row  gf  ga diff        L10 streak
            "%2s %-14s %2d %3d %3d %3d \x02%4d\x02 %4d %4d %4d $diffcolors %7s %5s",
            $rank,
            ($_->{clinchIndicator} ? "$_->{clinchIndicator}-" : "") . $_->{team}{locationName},
            $_->{gamesPlayed},
            $_->{leagueRecord}{wins},
            $_->{leagueRecord}{losses},
            $_->{leagueRecord}{ot},
            $_->{points},
            $_->{row},
            $_->{goalsScored},
            $_->{goalsAgainst},
            $diff,
            $lastten,
            $_->{streak}{streakCode}
        );
    }

    if( $wild ) {
        splice(@ret,4,0,sprintf( "%-17s %s", uc( $output[3]->{team}{division}{name} ), substr( $ret[0], 18 ) ));
        splice(@ret,8,0,"WILDCARD    ".substr( $ret[0], 12 ));
        $ret[10] = "\x1F" . $ret[10];
    }
    return @ret;

} #StandingsNHL

sub Standings {
#http://www.tsn.ca/datafiles/XML/NHL/standings.xml
    my @params = split( ' ', lc( shift ) );
    use constant { nhl=>1, nfl=>2, mlb=>3 };
    my $league = 0;
    my $url;

    if( $params[0] eq 'nhlstandings' ) {
        my @tmpret = StandingsNHL( "@params[1..$#params]" );
        if( $tmpret[0] !~ /^error/ ) {
            return @tmpret;
        } else {
            print "$tmpret[0]\n" if( DEBUG );
        }
        $league = nhl;
        $url = 'http://espn.go.com/nhl/standings';
    } elsif( $params[0] eq 'mlbstandings' ) {
        $league = mlb;
        $url = 'http://espn.go.com/mlb/standings';
        foreach( $params[1] ) {
            if( /^[an]l/ ) { }
            if( /^mlb$/ ) { }
            else { return 'Valid Leagues: AL NL'; }
        }
        if( !$params[2] && length( $params[1] ) > 2 ) {
            $params[2] = substr( $params[1], 2 );
            $params[1] = substr( $params[1], 0, 2 );
        }

        $_ = $params[2];
        if( /^e($|a)/ ) { $params[2] = 'east' }
        elsif( /^c($|e)/ ) { $params[2] = 'central' }
        elsif( /^w($|e)/ ) { $params[2] = 'west' }
        elsif( /^b$/ ) { $params[1] = 'mlb' }
        else { $params[2] = '' }

    } else {
        return;
    }

    if( $league == nhl ) {
        $url .= '/_/group/2' if( $params[1] =~ /^(?:ea|we)st$/ );
        #$url .= '/_/type/wildcard
        $url .= '/_/group/1' if( $params[1] eq 'nhl' );
    } elsif( $league == mlb ) {
        $url .= '/_/group/9' if( $params[1] eq 'mlb' );
        $url .= '/_/group/5' if( $params[2] eq '' );
    }

    #print $url, " $params[1] $params[2]\n";
    my $data = download( $url );

    $data =~ s/class="colhead">/!!MARKER!! class="colhead">/gs;
    $data .= '!!MARKER!!';
    $data =~ s/&nbsp;/ /sg ;
    $data =~ s/<tr><td[^>]+><img[^>]+?height="1".*?<\/tr>//sg;
    if( $league == mlb ) {
        $params[3] = $params[1];
        $params[1] = 'american' if( $params[1] eq 'al' );
        $params[1] = 'national' if( $params[1] eq 'nl' );
    }
    if( $league == mlb && length( $params[1] ) == 8 && $params[2] ) {
        $data .= '!!LEAGUE!!';
        $data =~ s/class="stathead">/!!LEAGUE!! class="stathead">/gs;
        my @leagues = ( $data =~ /class="stathead"(.*?)!!LEAGUE!!/gs );
        foreach( @leagues ) {
            if( /\Q$params[1]\E League/i ) {
                $data = "$_!!MARKER!!";
                last;
            }
        }
        $params[1] = $params[2] if( $params[2] );
    }

    my @divisions = ( $data =~ /class="colhead">(.*?)!!MARKER!!/gs );
    $divisions[$#divisions] =~ s/(.*?)<\/table>/$1/s if( @divisions );
    my @ret;

    foreach( @divisions ) {
        my( $name ) = ( /<td.*?>(.*?)</s );
        next if( $params[1] && ($params[1] !~ /\*/ ) && ($name !~ /\Q$params[1]\E/i) );
        #print $name, "\n";
        my( $tmp ) = ( /<td.*?(<td.*?)<\/tr>/s );

        my( @aitem, @arow );
        my @cats = ( $tmp =~ /<td[^>]*>(.*?)<\/td>/sg );
        if( $league == mlb && $url !~ /group/ ) {
            $name = uc( $params[3] ) . " $name";
        }
        while( length( $name ) < 12 ) { $name .= ' '; }
        unshift( @cats, $name );
        my @maxlen;
        for my $i ( 0 .. $#cats ) {
            $cats[$i] =~ s/<.*?>//g;
        }

        ( $tmp ) = ( /<\/tr>(.*?)$/s );
        my @rows = ( $tmp =~ /(<tr.*?)<\/tr>/sg );
        #print $rows[0], "\n";

        foreach( @rows ) {
            $_ = $1 if( /<tr [^>]+><td>[\d ]+<\/td>(.*)$/s );
            my @items = ( /<td[^>]*>\s*(.+?)\n*<\/td>/sg );
            if( @items > 3 ) {
                foreach( @items ) {
                    s/"greenfont">/>\x033/g;
                    s/"redfont">/>\x034/g;
                    s/<\/span>/\x03/g;
                    s/<.*?>//g;
                }
                push @aitem, [ @items ];
            }
        }

        my @columns;
        for my $i ( 0 .. $#cats ) {
            next if( $cats[$i] =~ /^(?:so[wl]|home|g[fa]|road|r[sa])$/i );
            my @column;
            my $extra = '';
            $extra = "\x02" if( $cats[$i] =~ /^pts$/i && $league == nhl );
            $extra = "\x02" if( $cats[$i] =~ /^gb$/i && $league == mlb );
            push @column, $extra . $cats[$i] . $extra;
            my $fixzero = 1 if( $cats[$i] =~ /^diff$/i );
            for my $j ( 0 .. $#aitem ) {
                if( $fixzero && $aitem[$j][$i] eq '0' ) {
                    push @column, "\x030 E\x03";
                } else {
                    push @column, $extra . $aitem[$j][$i] . $extra;
                }
            }
            push @columns, [ @column ];
        }

        #set maxlen
        for my $i ( 0 .. $#columns ) {
            for my $j ( 0 .. $#{$columns[$i]} ) {
                $columns[$i][$j] =~ s/(.) - /$1-/ if( $i == 0 );
                my $L = length( $columns[$i][$j] );
                $maxlen[$i] = $L if( !$maxlen[$i] || $maxlen[$i] < $L );
            }
        }
        #pad to maxlen
        for my $i ( 0 .. $#columns ) {
            for my $j ( 0 .. $#{$columns[$i]} ) {
                while( length( $columns[$i][$j] ) <= $maxlen[$i] ) {
                    $columns[$i][$j] .= ' ';
                }
            }
        }
        #push out
        for my $i ( 0 .. $#{$columns[0]} ) {
            if( $i > 0 ) {
                if( $league == nhl && $#{$columns[0]} == 15 ) {
                    $tmp = $i <= 8 ? "\x033" : "\x034";
                    $tmp .= sprintf( " %2d\x03 ", $i );
                } else {
                    $tmp = sprintf( " %2d ", $i );
                }
            } else {
                $tmp = "    ";
            }
            for my $j ( 0 .. $#columns ) {
                $tmp .= $columns[$j][$i];
                $tmp .= ' ' if( $tmp =~ /.......*?\x03/ );
            }
            push @ret, $tmp;
        }
    }
    return 'No matching conference or division found' if( !@ret );
    return @ret;
} #GetStandings

sub StatsPlayoffsESPN {

    my $search = shift;
    #print "looking up:$search.\n";
    my @params = split( ' ', $search );
    my $year = int( $params[$#params] );
    return "Locked out \x02(FUCK YOU BETTMAN)" if( $year == 2005 );

    if( $year == 0 ) {
        $year = -1 if( $search =~ /career$/i );
    }

    if( $year != 0 ) {
        pop( @params );
        $search = join( ' ', @params );
    }

    my %results = google( 'espn.go.com/nhl/player/', $search );
    my $url = '';
    for my $c ( 1 .. $results{count} ) {
        if( $results{url}[$c] =~ m!.*?espn\.go\.com/nhl.*?id/([0-9]+)! ) {
            #http://espn.go.com/nhl/player/_/id/904/mats-sundin
            #http://espn.go.com/nhl/player/stats/_/id/904/seasontype/3/mats-sundin
            $url = "http://espn.go.com/nhl/player/stats/_/id/$1/seasontype/3/";
            last;
        }
    }
    return "No results found" if( !$url );

    $_ = download( $url, 1 );
    my($name) = /playerName = '(.*?)'/s;
    my($data) = /<div class="player-bio">(.*)/s
        or return 'an error occured';
    my($c,$r) = $data =~ /POSTSEASON STATS<\/td><\/tr>(.*?)<\/tr>(.*?)<\/table>/s
        or return "No playoff stats for $name";

    my @cats = ( $c =~ /<td.*?>(.*?)</sg );
    my @rows = ( $r =~ /<tr.*?>(.*?)<\/tr/sg );
    my @row;

    for my $i ( 0 .. $#rows ) {
        my @items = ( $rows[$i] =~ /<td.*?>(.*?)<\/td>/sg );
        $items[0] =~ s/'([0-3])/20$1/sg ;
        $items[0] =~ s/'/19/sg ;
        unshift( @items, 'Career' ) if( $i == $#rows );
        for my $j ( 0 .. $#items ) {
            $row[$i]{$cats[$j]} = $items[$j];
        }
        $row[$i]{'TEAM'} =~ s/<.*?>//sg;
    }

    my $y = -1;
    my $ret = '';

    if( $year != -1 ) {
        if( $year == 0 ) {
            $y = $#row - 1;
        } else {
            for( my $i = $#row - 1; $i >= 0; $i-- ) {
                if( $row[$i]{'SEASON'} =~ /\-.*?$year$/ ) {
                    $y = $i;
                    last;
                }
            }
        }
        return 'No stats for that year' if( $y == -1 );
        $row[$y]{'SEASON'} =~ s/\-../\-/;
        $ret = "$name | Playoff stats | ";
        $ret .= $row[$y]{'SEASON'} . ' | ' . $row[$y]{'TEAM'};

    } else {
        $y = $#row;
        $ret = "$name | Career playoff stats | ";
        $ret .=  "YRS " . $y;
    }

    foreach( qw( GP G A PTS +/- PIM SOG % PPG PPA SHG SHA GWG W L GAA SA SV SV% SO ) ) {
        $ret .= " | $_ " . $row[$y]{"$_"} if( defined $row[$y]{"$_"} );
    }
    return $ret;

} #GetPStats

sub StatsHDB {

    my $search = shift;
    my @params = split( ' ', $search );
    my $year = $search =~ / career$/i ? -1 : $params[$#params];
    $search =~ s/ [^ ]+$// if( $year != 0 );

    my %results = google( 'hockeydb.com/ihdb/stats/', $search );
    return 'Player not found.' if( !$results{count} );
    my $data = download( $results{url}[1], 1 );

    return 'an error occured.' if( index( $data, 'content="Statistics ' ) == -1 );

    my( $name, $pos, $bdate, $bplace, $ht, $wt ) = $data =~
        /<h1.*?>(.*?)<.*?1">\R(.*?)<br \/>(.*?) -- (.*?)<br \/>Height (.*?) -- Weight (.*?)[ <]/s;
    my( $sc ) = $data =~ /-- (Shoots .)/si;
    foreach( $name, $pos, $bdate, $bplace, $ht, $wt, $sc ) {
        s/(<.*?>|\l\n)//g;
    }

    ($data) = ( $data =~ /(.*?)<\/table>/s );
    my @years = $data =~ /<tr>\R?<td class="pds l">(.*?)<\/tr>/sg;
    my @ret;
    my( $y, $r, $goalie ) = ( -1, 0, $pos =~ /goalie/i );
    $sc =~ s/shoots/Catches/i if( $goalie );
    $pos =~ s/--.*//;

    if( $year >= 0 ) {
        for( my $i = $#years; $i >= 0; $i-- ) {
            next if( $years[$i] !~ /"pdl l">NHL</s );
            if( $year == 0 ) {
                $y = $i;
                $i = 0;
            } elsif( $years[$i] =~ /^\Q$year\E/ ) {
                $y = $i;
                $i = 0;
            }
        }
        return 'No stats for that year' if( $y == -1 && $year != 0 );
        my( $team ) = $years[$y] =~ /a href.*?>(.*?)</s;
        if( $year == 0 ) {
            my( $draft ) = $data =~ /(?:Selected|Drafted) by (.*?)<\/div>/s;
            if( $draft ) {
                $draft =~ s/<.*?>|\R//g;
                $draft = " Drafted by $draft |";
            }
            $ht =~ s/(\d+)\.0?(\d+)/$1'$2"/;
            @ret = "$name | $team $pos $ht ${wt}lbs $sc |$draft $bdate - $bplace";
            $r++;
        } else {
            @ret = "$name | " . FindTeam( $team ) . " | ";
        }
        my( $season ) = $years[$y] =~ /(.*?)</;
        $ret[$r] .= $y >= 0 ? $season : "No NHL games played";
        return @ret if( $y == -1 );
    } else {
        if( $goalie ) {
            #no nhl totals :/
            my( %s );
            my( @cats ) = qw( GP A PIM Min GA EN SO GAA W L T Svs Pct );

            foreach( @years ) {
                next if( index( $_, '>NHL<' ) == -1 );
                my( @items ) = $_ =~ /<td>(.*?)<\/td>/sg;
                for my $i ( 0 .. $#cats ) {
                    next if( $cats[$i] =~ /^(?:PIM|EN|A|GAA|Pct)$/ );
                    $s{$cats[$i]} += $items[$i];
                }
            }
            $s{GAA} = sprintf( '%4.2f', $s{GA} / ( $s{Min} / 60 ) ) if( $s{Min} > 0 );
            $s{Pct} = sprintf( '%1.3f', $s{Svs} / ( $s{Svs} + $s{GA} ) ) if( ($s{Svs} + $s{GA}) > 0 );

            $ret[0] = "$name | Career stats";
            for my $i ( 0 .. $#cats ) {
                next if( $cats[$i] =~ /^(?:PIM|EN|A)$/ );
                $ret[0] .= " | $cats[$i] $s{$cats[$i]}";
            }
            return $ret[0];


        } else {
            my( $totals ) = $data =~ /"l">NHL Totals(.*?)<\/tr>/s;
            $totals =~ s/<td><\/td>/<td comment><\/td>/s;
            push @years, $totals;
        }
        $y = $#years;
        @ret = "$name | Career stats"
    }

    my @cats = $goalie ? qw( GP A PIM Min GA EN SO GAA W L T Svs Pct ) : qw( GP G A Pts PIM +/- );
    my @items = $years[$y] =~ /<td>(.*?)<\/td>/sg;

    pop @cats if( !$goalie && $year == -1 );
    for my $i ( 0 .. $#cats ) {
        next if( $goalie && $cats[$i] =~ /^(?:PIM|EN|A)$/ );
        $ret[$r] .= " | $cats[$i] $items[$i]" if( $items[$i] ne '&nbsp;' );
    }

    foreach( @ret ) { s/  +/ /g; }
    return @ret;
} #StatsHDB()

sub StatsNHL {
    $_ = shift;
    my( $playoffs ) = shift;
    my( $search, $year ) = /(.*?) ?([0-9-]+)$/ ? ($1,$2) : /(.*?) career$/i ? ($1,-1) : ($_,0);

    return "Locked out \x02(FUCK YOU BETTMAN)" if( $year == 2004 );
    if( $search =~ /^lemieux$/i ) { $search = 'mario lemieux' }
    elsif( $search =~ /^dink$/i ) { $search = 'claude giroux' }

    print "search: $search year: $year\n" if( DEBUG );

    my($fname,$lname) = $search =~ /([^ ]+) (\w.*)/ ? ($1,$2) : ('', $search);
    my($fletter) = $fname =~ /([a-z])/i ? "$1." : 'QQ';
    my(%google) = DEBUG ? (count=>0) : google( 'nhl.com/player/', $search );
    my $nhlid;
    for my $c ( 1 .. $google{count} ) {
        #http://www.nhl.com/player/david-perron-8474102
        if( $google{url}[1] =~ /player.*?(\d+)/ ) {
            $nhlid = $1;
            last;
        }
    }
    if( !$nhlid ) {
        #http://suggest.svc.nhl.com/svc/suggest/v1/minplayers/lemieux/99
        eval {
            my $js = decode_json( download( "http://suggest.svc.nhl.com/svc/suggest/v1/minplayers/$lname/100", 1 ) );
            foreach( @{$js->{suggestions}} ) {
                #"8448782|Lemieux|Mario|0|0|6\u0027 4\"|230|Montreal|QC|CAN|1965-10-05|PIT|C|66|mario-lemieux-8448782"
                my( @tokens ) = split /\|/;
                if( !$fname || $tokens[2] =~ /\Q$fname\E/i ) {
                    $nhlid = $tokens[0];
                    last;
                }
            }
        };
    }
    return 'player not found' if( !$nhlid );

    print "Found player id: $nhlid\n" if( DEBUG );
    my $js; my $url = "http://statsapi.web.nhl.com/api/v1/people/$nhlid?expand=person.stats&stats=yearByYear,yearByYearPlayoffs,careerRegularSeason,careerPlayoffs&expand=stats.team&site=en_nhlCA";
    eval { $js = decode_json( download( $url ) ); };
    foreach( @{ $js->{people} } ) {
        if( $_->{id} == $nhlid ) {
            $js = $_;
            last;
        }
    }
    return 'an error occured' if( !$js );

    my @stats = @{ $js->{stats} };
    my( $season, $statline, @ret );

    @stats = grep { $_->{type}{displayName} eq ("yearByYear" . ($playoffs ? "Playoffs" : "")) } @stats;
    if( $year <= -1 ) { #career
        my $years = grep { $_->{league}{id} && $_->{league}{id} == 133 } @{ $stats[0]->{splits} };
        @stats = grep { $_->{type}{displayName} eq ("career" . ($playoffs ? "Playoffs" : "RegularSeason")) } @{ $js->{stats} };
        @stats = @{ $stats[0]->{splits} };
        $statline = "$js->{fullName} | Career" . ( $playoffs ? " Playoffs | YRS $years" : "" );
    } else {
        if( $year ) {
            $season = $year . ($year + 1 );
            @stats = grep { $_->{season} eq $season && $_->{league}{id} == 133 } @{ $stats[0]->{splits} };
        } else {
            @stats = grep { $_->{league}{id} && $_->{league}{id} == 133 } @{ $stats[0]->{splits} };
            $season = $stats[$#stats]->{season} if( @stats );
            @stats = grep { $_->{season} eq $season } @stats;
        }
        $statline = "$js->{fullName} | " if( $year );
        $statline .= "$1-$2" if( $season =~ /(....)..(..)/ );
        $statline .= ($playoffs ? " Playoffs" : "") . " | " . $stats[0]->{team}{abbreviation};
    }

    if( !$year ) { #were gonna need draft data

#16:46 < stats> Phil Kessel | Pittsburgh #81 RW 6-0 202lbs | Drafted 2006 1ˢᵗ round (5ᵗʰ pick) by the Boston Bruins | Born October 2, 1987 - Madison, Wisconsin
        $js->{currentTeam}{name} = $stats[0]->{team}{name} if( ! $js->{currentTeam}{name} );
        @ret = "$js->{fullName} | $js->{currentTeam}{name} #$js->{primaryNumber} $js->{primaryPosition}{abbreviation} "
            . $js->{height} =~ s/ //r . " $js->{weight}lbs | Born " . GetDate( $js->{birthDate}, '%b %e, %Y' )
            . " in $js->{birthCity}, " . ($js->{birthStateProvince} ? "$js->{birthStateProvince}, " : "") . $js->{birthCountry};

        eval {
            my $url = "http://www.nhl.com/stats/rest/skaters?reportType=basic&reportName=bios&cayenneExp=playerId=$nhlid";
            $url =~ s/skaters/goalies/ if( $js->{primaryPosition}{abbreviation} eq 'G' );
            my $bio = decode_json( download( $url, 1 ) );
            if( $bio = $bio->{data}->[0] ) {
                my $draft = $bio->{playerDraftYear} ? "Drafted $bio->{playerDraftYear} Rd $bio->{playerDraftRoundNo} (\#$bio->{playerDraftOverallPickNo} overall)" : "Undrafted";
                $ret[0] =~ s/Born/$draft \| Born/;
            }
        };

        if( ! $stats[0]->{stat}{games} ) {
            push @ret, "No stats found";
            return @ret;
        }
    } else {
        return "No stats found that year" if( ! $stats[0]->{stat}{games} );
    }

    my %tally;
    for my $i ( 0 .. $#stats ) {
        $statline .= "/" . $stats[$i]->{team}{abbreviation} if( $i > 0 );
        for my $key ( keys %{$stats[$i]->{stat}} ) {
            foreach( $stats[$i]->{stat}{$key} ) {
                if( /\d+\:\d+/ ) {
                    $tally{$key} += $1 * 60 + $2 if( $stats[$i]->{stat}{$key} =~ /(\d+)\:(\d+)/ );
                } elsif( /\d+\.\d+/ ) {
                    # shotPct, evenStrengthSavePercentage, savePercentage, goalAgainstAverage
                    # recalculate below after its all been tallied
                    # print "unparsed % stat: $key | $_\n" if( DEBUG );
                } elsif( /\-?\d+/ ) {
                    $tally{$key} += $stats[$i]->{stat}{$key};
                } else {
                    #print "unparsed default stat: $key | $_\n" if( DEBUG );
                    $tally{$key} += $stats[$i]->{stat}{$key};
                }
            }
        }
    }

    if( $js->{primaryPosition}{abbreviation} eq 'G' ) {
        $tally{savePercentage} = sprintf( '%.3f', $tally{saves} / $tally{shotsAgainst} ) if( $tally{shotsAgainst} );
        $tally{goalAgainstAverage} = sprintf( '%4.2f', ( 60*60 / $tally{timeOnIce} ) * $tally{goalsAgainst} ) if( $tally{timeOnIce} );
    } else {
        $tally{shotPct} = sprintf( '%0.1f', $tally{goals} / $tally{shots} * 100 ) if( $tally{shots} );
        #faceoffssssssss
        eval {
            my $fo = decode_json( download( "http://www.nhl.com/stats/rest/skaters?reportType=basic&reportName=faceoffs&cayenneExp=playerId=$nhlid%20and%20gameTypeId=" .($playoffs ? "3" : "2"). ($year >= 0 ? "%20and%20seasonId=$season" : ""), 1 ) );
            foreach( @{ $fo->{data} } ) {
                $tally{faceOffWins} += $_->{faceoffsWon};
                $tally{faceOffLosses} += $_->{faceoffsLost};
            }
        };
        if( my $faceoffs = $tally{faceOffWins} + $tally{faceOffLosses} ) {
            $tally{faceOffPct} = sprintf( '%2.1f', $tally{faceOffWins} / $faceoffs * 100 );
        } else {
            $tally{faceOffPct} = $tally{faceOffWins} = $tally{faceOffLosses} = 0;
        }
    }

#16:46 < stats> 2016-17 | PIT | GP 63 | G 21 | A 37 | PTS 58 | +/- 1 | PIM 18 | HITS 9 | BKS 13 | FW 4 | FL 10 | FO% .286 | PPG 8 | PPA 19 | SHG 0 | SHA 0 | GW 4 | SOG 174 | PCT .121
    my @cats;
    if( $js->{primaryPosition}{abbreviation} ne 'G' ) {
        @cats = qw/games goals assists points plusMinus pim hits blocked faceOffWins faceOffLosses faceOffPct timeOnIce powerPlayGoals powerPlayPoints shortHandedGoals shortHandedPoints gameWinningGoals shots shotPct/;
    } else {
        #2016-17 | MON | GP 52 | GS 52 | MIN 3108 | W 31 | L 16 | OTL 5 | EGA 4 | GA 117 | GAA 2.26 | SA 1522 | SV 1405 | SV% .923 | SO 3
        @cats = qw/games gamesStarted timeOnIce wins losses ot ties shutouts goalsAgainst goalAgainstAverage shotsAgainst saves savePercentage/;
    }
    foreach( @cats ) {
        next if( ! $tally{$_} && /hits|pim|timeOnIce|blocked|Points|Started|shotsAgainst|save/ );
        if( /^(goals|assists|points|wins|losses)$/ ) {
            $statline .= " | " . uc substr( $1, 0, 1 ) }
        elsif( /^(pim|hits)$/ ) {
            $statline .= " | " . uc $1 }
        elsif( /(.).*?(\P{IsLower}+).*?(G)oals/ ) {
            $statline .= " | " . uc "$1$2$3" }
        elsif( /(.).*?(\P{IsLower}+).*?Points/ ) {
            $statline .= " | " . uc "$1$2A ";
            $statline .= $tally{$_} - $tally{$1 eq 's' ? "shortHandedGoals" : "powerPlayGoals"};
            next;
        }
        elsif( /^timeOnIce$/ ) {
            use integer;
            if( $js->{primaryPosition}{abbreviation} ne 'G' ) {
                $statline .= sprintf( " | TOI %d:%02d", $tally{$_} / 60 , $tally{$_} % 60 );
                $statline .= sprintf( " | TOI/G %d:%02d", $tally{$_} / 60 / $tally{games}, ( $tally{$_} / $tally{games} ) % 60 ) if( $tally{games} );
            } else {
                $statline .= " | MIN " . ($tally{$_} / 60);
            }
            next;
        }
        elsif( /^(ot|ties)$/ ) {
            next if( !$tally{$_} );
            $statline .= " | " . uc $1;
        }
        elsif( /(?|(g)ames(S)tarted|(g)oals(A)gainst|(g)oal(A)gainst(A)verage|(s)hots(A)gainst|(s)a(v)es|(s)hut(o)uts)/ ) {
            $statline .= " | " . uc "$1$2" . ( $3 ? uc $3 : "") }
        elsif( /faceOff(.)/ ) {
            next if( ! $tally{faceOffPct} );
            $statline .= " | FO" . ($1 eq "P" ? "%" : $1) }
        elsif( /^savePercentage/ ) {
            $statline .= " | SV%" }
        elsif( /^shot(s|Pct)$/ ) {
            $statline .= " | SOG" . ($1 ne "s" ? "%" : "") }
        elsif( /^games$/ ) {
            $statline .= " | GP" }
        elsif( /^blocked$/ ) {
            $statline .= " | BKS" }
        elsif( /^plusMinus$/ ) {
            $statline .= " | " . ($tally{$_} >= 0 ? "+" : "") . $tally{$_};
            next;
        } else {
            print "unparsed key: $_\n" if( DEBUG );
            $statline .= " | $_";
            next;
        }
        $statline .= " $tally{$_}";
    }

    push @ret, $statline;
    return $statline if( $year != 0 );
    return @ret ? @ret : 'no stats found';

}

sub ScoresIIHF {
    #{"n":"62","d":"2017-05-20","t":"19:15 GMT+2","v":"1","p":"SF","e":"2","h":"SWE","g":"FIN",},
    #{"n":"55","d":"2017-05-16","t":"20:15 GMT+2","v":"1","p":"PRE","group":"A","e":"7","h":"GER","g":"LAT","r":"4-3","s":"GWS",},
    
    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    $date = GetDate( '6 hours ago', '%Y-%m-%d' ) if( !$date );
    my( $year ) = $date =~ /(....)/;
    print "ScoresIIHF: $search | $date\n" if( DEBUG );
    
    my( $data ) = download( "http://d.widgets.iihf.hockey/Hydra/${year}-WM/widget_en_${year}_wm_tournament.js" );
    $data =~ s/.*?games: \[(.*?)\].*/$1/s;
    my @ret;
    foreach( grep { /"d":"$date/ } $data =~ /(\{.*?\})/sg ) {
        my %g = simplejson( $_ );        
        if( $g{e} == 7 ) {
            my( $score_home, $score_away ) = $g{r} =~ /(\d+)-(\d+)/;
            push @ret, "$g{g} $score_away $g{h} $score_home ( Final" . ($g{s} == 3 ? "" : "/$g{s}") . " )";
        } elsif( $g{e} == 2 ) {
            foreach( $g{g}, $g{h} ) { $_ = "TBD" if( !$_ ) }
            push @ret, "$g{g} @ $g{h} ( " . GetDate( $g{t}, '%-I:%M%p ET' ) . " )";
        } else {
            push @ret, ScoresIIHFhtml( "$g{g} $g{h}", $date );
        }
    }
    return @ret ? @ret : "no games found";

}

sub ScoresIIHFhtml {
    
    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    $date = "(?:" . GetDate( '6 hours ago', '%Y-%m-%d' ) . "|wm_live)" if( !$date );
    my( $year ) = $date =~ /(\d{4})/;
    print "ScoresIIHFhtml: $search | $date\n" if( DEBUG );
    
    #<div id=\"date-2017-05-05\" class=\"game-day\"><div title=\"Click here to open Game Summary\" data-url=\"/en/games/2017-05-05/SWE-vs-RUS/\" class=\"played page-linker\">
    #<div class=\"title\">Game Completed</div><div class=\"game\"><img src=\"http://s.widgets.iihf.hockey/Hydra/flags/30x22/SWE.png\" class=\"flag left\" alt=\"Sweden\" title=\"Sweden\"><span class=\"team left\">SWE</span>
    #<span class=\"result active\">1 - 2</span>
    #<span class=\"team right\">RUS</span><img src=\"http://s.widgets.iihf.hockey/Hydra/flags/30x22/RUS.png\" class=\"flag left\" alt=\"Russia\" title=\"Russia\"></div><div class=\"game-info\">
    #<span class=\"game\">Preliminary Round - Group A Game 1</span><span class=\"venue\">LANXESS arena</span></div></div>
    my( $data ) = download( "http://d.widgets.iihf.hockey/Hydra/${year}-WM/widget_en_${year}_wm_scoreboard.html" );
    my( @games ) = $data =~ m!.*?(data-url=\\"[^"]+?$date.*?</div></div>)!sg;
    my @ret;
    foreach( @games ) {
        my( $team_left ) = /team left.*?>(.*?)</;
        my( $team_right ) = /team right.*?>(.*?)</;
        my( @full_teams ) = /flag .*?title=\\"(.*?)\\"/sg;
        if( !$search || $search eq '*' || "$team_right $team_left @full_teams" =~ /\Q$search\E/i ) {
            my( $score_left, $score_right ) = /(\d+) - (\d+)/; #IIHF does home team on the left...meh
            my $tmp = "$team_right $score_right $team_left $score_left ( ";
            $tmp .= (/Game Completed/ ? "Final" : (/<span>LIVE<\/span>(.*?)</ ? $1 : "")) . " )";
            push @ret, $tmp;
        }
    }
    return @ret ? @ret : "no games found";
        
    #live live-game-linker\"><div class=\"title\"><span class=\"live-flag\"><span>LIVE</span>Period 1 Ended</span>
}
    
sub ScoresTSN {
    print "ScoresTSN()\n" if( DEBUG );
    my( $league, $search, $date ) = @_;
    if( $search eq '*' ) {
        $search = '';
    }
    $date = GetDate( $date, '%Y%m%d' );
    $date = GetDate( 'now', '%Y%m%d' ) if( $date =~ /invalid/ );
    #http://stats.tsn.ca/ZRANGEBYSCORE/urn:tsn:wjhc:schedule/20141226/20141226.json
    #http://stats.tsn.ca/GET/urn:tsn:nfl:scoreboard?type=json
    #http://stats.tsn.ca/HGET/urn:tsn:mls:schedule/reg-11?type=json
    #http://stats.tsn.ca/GET/urn:tsn:mls:scoreboard?type=json
    my( $url ) = 'http://stats.tsn.ca/ZRANGEBYSCORE/urn:tsn:';
    foreach( lc( $league ) ) {
        if( /^(nhl|nba|mlb)$/ ) {
            $url .= "$1:schedule/$date/$date.json"; }
        elsif( /^(nfl|cfl|mls)$/ ) {
            my $tmp = $1;
            $url =~ s/ZRANGEBYSCORE.*/GET\/urn:tsn:$tmp:scoreboard?type=json/; }
        elsif( /^wj/ ) {
            $url .= "wjhc:schedule/$date/$date.json"; }
        elsif( /^(i+hf|wh|wor)/ ) {
            $url .= "wmhc:schedule/$date/$date.json"; }
        else{
            return; }
    }

    $httpref = $url =~ /urn:tsn:(.*?):/ ? "http://www.tsn.ca/$1/scores" : "";
    my $data = download( $url, 1 );
    $httpref = "";
    my( $js, @ret, $games );
    eval {
        $js = decode_json( $data );
        if( $league =~ /nfl|cfl|mls/i ) {
            #{"SeasonType":"post-20","isCurrentWeek":true,"Week":"20"
            for( my $w = 0; exists $js->[$w]; $w++ ) {
                $games = $js->[$w]->{Games} if( $js->[$w]->{isCurrentWeek} );
            }
        } else {
            $games = ref( $js ) eq 'HASH' ? from_json( $js->{(%$js)[0]}[0] )->{Games} : $js->[0]->{Games};
        }
    };

    return 'no games found' if( $@ || !$games );
    my $linescore = $league =~ /mlb/ ? 0 : 1;

    foreach( @$games ) {
        next if( $search && $_->{Id} !~ /\Q$search\E/i && "$_->{Home}{Team}{Acronym} $_->{Away}{Team}{Acronym}" !~ /\Q$search\E/i );
        #print Dumper( $_ ) if( DEBUG );

        if( $_->{State} ne 'PreGame' ) {
            if( $linescore ) {
                push @ret, "$_->{Away}{Team}{Acronym} $_->{Away}{Linescore}{Score} "
                    . "$_->{Home}{Team}{Acronym} $_->{Home}{Linescore}{Score} ( $_->{StateDetails} )";
            } else {
                push @ret, "$_->{Away}{Team}{Acronym} $_->{Away}{Runs} "
                    . "$_->{Home}{Team}{Acronym} $_->{Home}{Runs} ( $_->{StateDetails} )";
            }
        } else {
            push @ret, "$_->{Away}{Team}{Acronym} @ $_->{Home}{Team}{Acronym} ( $_->{StateDetails} )";
        }

    }
    return ( @ret ? @ret : 'no results found' );
} #ScoresTSN( )

sub ScoresNHL {
    
    #http://statsapi.web.nhl.com/api/v1/schedule?startDate=2017-09-21&endDate=2017-09-21&expand=schedule.linescore,schedule.broadcasts.all
    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    my( @ret, $js );
    
    undef $search if( $search eq '*' );
    $date = GetDate( '-12 hours', '%Y-%m-%d' ) if( !$date );    
    my( $data ) = download( "http://statsapi.web.nhl.com/api/v1/schedule?startDate=$date&endDate=$date&expand=schedule.linescore,schedule.broadcasts.all", 1 );
    eval { $js = decode_json( $data ) };
    return "nhl.com error occured" if( $@  );    
    
    foreach( @{ $js->{dates}->[0]->{games} } ) {
        my @teams = ( $_->{teams}->{away}->{team}->{name}, $_->{teams}->{home}->{team}->{name} );
        my @teamsabv = ( FindTeam( $teams[0], 1 ), FindTeam( $teams[1], 1 ) );
        next if( $search && "@teams @teamsabv" !~ /\Q$search\E/i );
        my $tmp = $teamsabv[0] . " ";
        if ( $_->{status}{statusCode} < 3 ) { #not started
            $tmp .= GetDate( $_->{gameDate}, "@ $teamsabv[1] ( %-I:%M %p %Z )" );
        } else {
            $tmp .= $_->{linescore}{teams}{away}{goals} . " " . $teamsabv[1] . " " . $_->{linescore}{teams}{home}{goals} . " ( ";
            if( $_->{status}{statusCode} >= 6 ) { #game is final
                $tmp .= "Final" . ( $_->{linescore}{currentPeriod} == 3 ? "" : "/" . $_->{linescore}{currentPeriodOrdinal} ) . " )";
            } else {
                $tmp .= $_->{linescore}{currentPeriodTimeRemaining} ." ". $_->{linescore}{currentPeriodOrdinal} . " )";
            }
        }
        if( $_->{status}{statusCode} < 6 && $#{ $_->{broadcasts} } >= 0 ) {
            $tmp .= $_->{name} . "," foreach( @{ $_->{broadcasts} } );
            $tmp =~ s/\)(.*?),$/\) \[$1\]/;
        }
                 
        push @ret, $tmp;        
        
    }
    
    return ( @ret ? @ret : ( $search ? 'no matching results' : "no games on $date" ) );
    
} #ScoresNHL()

sub ScoresNHLold {

    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    my( @ret, $liveonly );

    $date = GetDate( '-12 hours', '%Y-%m-%d' ) if( !$date );
    if( !$search ) {
        $liveonly = 1;
    } elsif( $search eq '*' ) {
        $search = '';
    }

    my( $data ) = download( "http://live.nhl.com/GameData/GCScoreboard/$date.jsonp", 1 ) =~ /loadScoreboard\(\{"games":\[(.+?)\]/s
        or return "no games for $date";

    foreach( $data =~ /\{(.*?)\}/sg ) {
        my( %js ) = simplejson( $_ );
        #print "JSON: $_\n\n";
        my $fullteams = "$js{atn} $js{atcommon} $js{htn} $js{htcommon}";
        my $abrevs = "$js{ata} $js{hta}";
        #print "full: $fullteams abv: $abrevs\n" if( DEBUG );
        my $tv = "$js{usnationalbroadcasts},$js{canationalbroadcasts}" =~ /(\w.*?),?$/ ? " [$1]" : '';
        if( !$search || $fullteams =~ /\Q$search\E/i || $abrevs =~ /\Q$search\E/i || $search eq $js{id} ) {
            if( $js{gs} == 1 ) { push @ret, "$js{ata} @ $js{hta} ( $js{bs} ET )$tv" if( !$liveonly ) }
            elsif( $js{gs} == 2 ) { push @ret, "$js{ata} @ $js{hta} ( Pregame )$tv" if( !$liveonly ) }
            elsif( $js{gs} == 5 ) { push @ret, "$js{ata} $js{ats} $js{hta} $js{hts} ( $js{bs} )" if( !$liveonly ) }
            else { push @ret, "$js{ata} $js{ats} $js{hta} $js{hts} ( $js{bs} )$tv" }
        }
    }
    return @ret ? @ret : 'No Results Found';
} #ScoresNHLold()

sub Scores {

    my( $league, $params ) = split( ' ', lc shift, 2 );
    my( $football, $url );
    
    if( $league eq 'nhl' ) {
        return ScoresNHL( $params );
    } else {
        my( $search, $date ) = SplitDate( $params, '%Y-%m-%d' );
        return ScoresTSN( $league, $search, $date );
    }

} #Scores( )

sub GoalRND {

    my( $season, $hq ) = @_;
    my( $today ) = GetDate( 'now', '%Y%m%d' );
    $season = (substr($today,4,2) > 9 ? substr($today,0,4) : substr($today,0,4)-1) if( !$season );
    my $json = download( "http://live.nhl.com/GameData/SeasonSchedule-$season" . ($season+1) . ".json" );
    eval { $json = decode_json( $json ) };
    return 'an error occured' if( $@ );

    my( $ret, $rnd );
    my( $max ) = 0;
    my @games = sort { $a->{'est'} cmp $b->{'est'} } @$json;
    foreach( @games ) {
        $max++;
        last if( $_->{'est'} gt $today );
    }

    for( my $i = 0; $i < 3; $i++ ) {
        $rnd = int( rand( $max ) );
        print "selecting game \#$rnd of $max\n" if( DEBUG );
        my $date = substr( $games[$rnd]->{'est'}, 0, 8 );
        my @scores = ScoresNHL( $games[$rnd]->{'h'} . " $date" );
        print "scores: @scores\n" if( DEBUG );
        my $goals = $scores[0] =~ /(\d+).*?(\d+)/ ? $1 + $2 : 1;
        my $goal = int( rand( $goals ) ) + 1;
        print "selecting goal $goal of $goals\n" if( DEBUG );
        $ret = GoalVid( $games[$rnd]->{$goal > $1 ? 'h' : 'a'} . " " . ($goal > $1 ? $goals-$1 : $goal) . " $date", $hq );
        if( $ret =~ /http/ ) {
            $ret .= GetDate( $date, " -- %a %b %d, %Y" );
            last;
        }
    }
    return length( $ret ) > 25 ? $ret : 'an error occured';
}

sub OlympicsOdds {
    $_ = download( 'http://sports.bovada.lv/sports-betting/olympic-hockey-lines.jsp' );
    s/(<div class="schedule-date">)/_!_MARKER$1/sg;
    my @ret;
    my( $now ) = time;
    foreach( /<div class="schedule-date">(.*?)(?:_!_MARKER|$)/sg ) {
        my( $day ) = /(?:<.*?>)*(.*?)</ ? $1 : "";
        my $lastteam;
        foreach( /div class="event-name">[^<]*?Men.*?<(.*?<\/table.*?)<\/table/sg ) {
            my $time = /div class="time-open".*?>(.*?)</s ? $1 : "";
            my @team = /div class="competitor-name".*?>(.*?)<\/div/sg;
            my @puckline = /<div class="line-.*?>(.*?)<\/div/sg;
            my @moneyline = /<div class="moneyline-.*?>(.*?)<\/div/sg;
            foreach( @team, @puckline, @moneyline ) { s/(&nbsp;)+/ /sg; s/<.*?>|\s*\R\s*//sg; }
            foreach( @team ) { s/\s*\(.*?\)\s*//g; }
            my( $epoch ) = `date -d '$day ${time}m' +%s` =~ /(.*)/;
            next if( !$puckline[1] || /class="disabled"/ || $lastteam eq $team[0] || abs($epoch - $now) > (3600*24*2) );
            $lastteam = $team[0];
            ($time) = `date -d '\@$epoch' '+(%b %d %I:%M%p ET)'` =~ /(.*)/; #TZ="America/Chicago"
            push @ret, "$team[0] [$puckline[0]/$moneyline[0] SU] vs $team[1] [$puckline[1]/$moneyline[1] SU] $time";
        }
    }
    return @ret ? @ret : 'error getting odds';
}


sub BettingOdds {
    my( $league, $search, $date ) = split( ' ', shift, 2 );
    ($search,$date) = SplitDate( $search, '%Y-%m-%d' );
    my( @ret, $url );

    $search = '' if( $search eq '*' );
    foreach( lc( $league ) ) {
        if( /^(nhl|nfl|mlb|nba)$/ ) { $url = "http://sports.yahoo.com/$1" }
        elsif( /^ncb$/ ) { $url = "http://rivals.yahoo.com/ncaa/basketball" }
        elsif( /^ncf$/ ) { $url = "http://rivals.yahoo.com/ncaa/football" }
        elsif( /^oly/ ) { return OlympicsOdds( $search ) }
        else { return 'Valid leagues: NHL NFL MLB NBA NCF NCB' }
    }

    my $data = download( "$url/odds/moneyline?day=" . ($date ? $date : GetDate( 'today', '%Y-%m-%d' ) ) );
    my @games = $data =~ /<td class="teams .*?">(.*?)<\/tr>/sg;

    return 'No games left today' if( !@games );

    my @sites = ($1,$2,$3,$4) if( $data =~ /<th class="teams">Teams(.*?<th>[^<]+)((?1))((?1))((?1))/s );
    my $column;
    for( $column = 0; $column < $#sites; $column++ ) { last if( $sites[$column] =~ /BETONLINE/i ); }
    print "using column $column ($sites[$column])\n" if( DEBUG );

    foreach( @games ) {
        my( @odd ) = /<span.*?>([\+\-]\d+|Even|N\/A)/sg;
        my( $date ) = /<div>\s*<span>(.*?)</s;
        my( @teams ) = /<span class="team"><a [^>]*>(.*?)</sg;
        if( !$search || join( ' ', @teams ) =~ /\Q$search\E/si ) {
            for( my $o = 0; $o <= $#odd; $o++ ) {
                if( $odd[$o] =~ /([0-9-]+)/ ) {
                    $odd[$o] .= sprintf "/%.3g", ( $1 < 0 ? -100/$1+1 : $1/100+1 );
                } elsif( $odd[$o] eq 'N/A' ) {
                    splice( @odd, $o, 0, 'N/A' );
                    $o++;
                }
            }
            if( $league =~ /nhl/i ) {
                foreach( @teams ) { $_ = FindTeam( $_ ) }
            }
            push @ret, sprintf( "%-15s", "$teams[0] (" . $odd[$column*2] . ")" )
                . sprintf( "%-18s", " @ $teams[1] (" . $odd[$column*2+1] . ")" ) . " [$date]";
        }
    }
    return ( @ret ? @ret : 'error getting odds' );
} #BettingOdds

sub Rookies{
    my $num = shift;
    return "Usage: rookies <1-5>" if( $num < 1 );
    my @ret;
    my $data = download( 'http://www.nhl.com/ice/rookies.htm' );
    my ($table) = ( $data =~ /stats">(.*?)<\/table>/s);
    my (@players) = ( $table =~ /<tr.*?>(.*?)<\/tr>/gs );
    return 'No rookies found' if( @players <= 0 );

    shift @players; shift @players;
    #                   RANK NAME  TEAM POS  GP   G    A    P    +/-  PIM  PPG  SOG  SHT% GWG
    my $format       = "%-2s %-20s %-4s %-3s %-3s %-3s %-3s %-3s %-7s %-3s %-3s %-4s %-5s %-3s";
    my $formatheader = "%-2s %-20s %-4s %-3s %-3s %-3s %-3s %-3s %-4s %-3s %-3s %-4s %-5s %-3s";

    push @ret, "\x02\x1F" . sprintf( $formatheader, "RK", "PLAYER", "TEAM", "POS", "GP", "G", "A", "P", "+/-", "PIM", "PPG", "SOG", "SHOT%", "GWG" );

    foreach( @players ) {
        my ($rank, $player, $team, $pos, $gp, $goals, $assists, $points, $plusminus, $pim, $ppg, $ppp, $shg, $shp, $gw, $ot, $shots, $pct)
            = /<td.*?>(?:\s*<.*?>)?([^<]+)/sg;
        if( $plusminus != 0 ) {
            $plusminus = "\x03" . ( $plusminus > 0 ? "3" : "4" ) . "$plusminus\x03";
        } else {
            $plusminus = "\x038E\x03";
        }
        push @ret, sprintf($format, $rank, $player, $team, $pos, $gp, $goals, $assists, $points, $plusminus, $pim, $ppg, $shots, $pct, $gw);
        last if (@ret > $num);
    }
    return @ret;
} #Rookies

sub OlympicsSched {
    my( $search, $date ) = SplitDate( shift, '%Y-%m-%d' );
    if( !$date ) {
        $date = GetDate( $search, '%Y-%m-%d' );
        $search = '*' if( $date !~ /invalid/ );
    }
    $date = GetDate( 'today', '%Y-%m-%d' ) if( !$date || $date =~ /invalid/ );
    print "OlmypicsSched( $search )\n" if( DEBUG );
    undef $search if( $search eq '*' );

    my $data = download( "http://olympics.cbc.ca/schedules-results/day=$date/index.html" );
    return 'error getting data' if( !$data );
    my @ret;
    foreach( $data =~ /"or-disc-title">(.*?)<\/table/sg ) {
        my( $sport ) = /(.*?)</;
        next if( $search && $sport !~ /\Q$search\E/i );
        push @ret, uc "     -[ $sport ]-";
        foreach( /<td class="or-ses-time"(.*?<\/td.*?<\/td)/sg ) {
            my( $event ) = /"or-evt-phase.*?>(.*?)</s;
            my( $time ) = /data-or-utc="(\d{8})(\d{4})/s ? GetDate( "$1 $2 UTC", '%I:%M %p ET' ) : "";
            my( @teams ) = /"or-tri-name.*?>(.*?)</sg;
            if( @teams ) {
                push @ret, "$event - $teams[0] vs $teams[1] ($time)";
            } else {
                push @ret, "$event ($time)";
            }
        }
    }
    return 'no results found' if( !@ret );
    return @ret;
}

sub OlympicsMedals {
    my $search = lc shift;
    my $data = download( 'http://www.sochi2014.com/en/medal-standings' );
    my( @ret, %team, $sort, @sorted );
    my $c = 0;
    return 'error getting data' if( !$data );
    foreach( $data =~ /<tr>(.*?)<\/tr/sg ) {
        my( $abv, $full ) = /class="country (\w+).*?href=.*?>(.*?)</s or next;
        $team{$abv}{full} = $full;
        my( $r,$g,$s,$b,$t ) = /<td>(.*?)</sg;
        ($team{$abv}{g},$team{$abv}{s},$team{$abv}{b},$team{$abv}{t}) = ($g,$s,$b,$t);
        $c++;
        $team{$abv}{rank} = $r =~ /(\d+)/ ? $1 : $c;
        $team{$abv}{pts} = $g*3 + $s*2 + $b*1;
    }
    if( $search =~ /-sort (\w+)/i ) {
        $sort = lc $1 if( $1 =~ /([gsbt])/i );
        $search =~ s/ ?-sort \w+ ?//i;
        @sorted = sort { $team{$b}{$sort} <=> $team{$a}{$sort} ||
                        $team{$b}{pts} <=> $team{$a}{pts} ||
                        $team{$a}{full} cmp $team{$b}{full}
                } keys %team;
    } else {
        @sorted = sort { $team{$a}{rank} <=> $team{$b}{rank} } keys %team;
    }
    print "medals search=$search sort=$sort\n" if( DEBUG );
    my $rank = 0;
    my $prevteam = 999;
    $c = 0;
    foreach( @sorted ) {
        if( $sort ) {
            $c++;
            $rank = $c if( $team{$_}{$sort} < $prevteam );
            $prevteam = $team{$_}{$sort};
        } else {
            $rank = $team{$_}{rank};
        }
        my $tmp = "$rank. $team{$_}{full} | $team{$_}{g}G | $team{$_}{s}S | $team{$_}{b}B | Total $team{$_}{t}";
        if( !$search ) {
            push @ret, $tmp;
            return @ret if( $#ret >= 4 );
        } elsif( $team{$_}{full} =~ /\Q$search\E/i || $_ =~ /^\Q$search\E$/i ) {
            return $tmp;
        }
    }
    return ( $search ? 'team not found' : 'error occured' );
}

sub getRW {
    return(
        "\x030,8          \x034,8                    \x030,8  \x03",
        "\x030,8 \x034,8 \x034,0__________________________/_\x034,8 \x030,8 \x03",
        "\x030,8  \x030,0  \x034,3 \x031,030  20 \x031,7 40  6\x031,070  80 \x031,4 100\x034,4/\x031,0 \x030,0 \x030,8  \x03",
        "\x030,8 \x034,8 \x034,0________________________/___\x034,8 \x030,8 \x03",
        "\x030,8  \x030,0   \x034,0       \x039,0ARBITER\x034,0   \x030,0   \x034,0/\x030,0    \x030,8  \x03",
        "\x030,8  \x030,0     \x034,0   \x039,0RAGE-O-METER\x0313,0 \x030,0 \x034,0/\x030,0     \x030,8  \x03",
        "\x030,8  \x030,0      \x034,0 \x030,14 \x034,14 \x030,14            \x034,0/\x030,0      \x030,8  \x03",
        "\x030,8                           \x038,8   \x030,8  \x03"
    );
}

sub BoldScore {
    my( $t1, $s1, $t2, $s2 ) = $_[0] =~ /([\w .-]+?) (\d+) ([^\(]+?) (\d+) ?(?:\(|$)/ or return;
    return if( $s1 == $s2 );
    my $t = $s1 > $s2 ? $t1 : $t2;
    $_[0] =~ s/($t \d+)/\x02$1\x02/;
}

sub SplitDate {
    my( $d, $fmt ) = @_;
    $_ = $d;
    print "SplitDate: $_ -- $fmt | " if( DEBUG );
    my( $team, $date ) = ( /((?:\w+ |\* )+?)((?:last|next)? *\S+)\s*$/i || /(.*?)(\d+.*)/ ) ? ($1,$2) : ($_,'');
    $team =~ s/\s+$//;
    $team = '*' if( !$team && $date );
    if( $date ) {
        $date = GetDate( $date, $fmt );
        if( $date =~ /invalid/ )
            { $date = ""; $team = $_; }
    }
    print "T:$team | D:$date\n" if( DEBUG );
    return ( $team, $date );
}

sub calcsize {
    my $tmp = shift;
    if      ($tmp >= 2**40) { return sprintf( '%.2f TB', $tmp / 2**40 ) }
    elsif   ($tmp >= 2**30) { return sprintf( '%.2f GB', $tmp / 2**30 ) }
    elsif   ($tmp >= 2**20) { return sprintf( '%.2f MB', $tmp / 2**20 ) }
    elsif   ($tmp >= 2**10) { return sprintf( '%.2f KB', $tmp / 2**10 ) }
    else                    { return "$tmp B" }
}

sub pformat {
    my( $n, $f ) = @_;
    my $ret;
    if( $n > 999999999 ) {
        $ret = sprintf( "$f".'B', $n / 1000000000 )
    } elsif( $n > 999999 ) {
        $ret = sprintf( "$f".'M', $n / 1000000 )
    } elsif( $n > 999 ) {
        $ret = sprintf( "$f".'K', $n / 1000 )
    } else {
        $ret = $n
    }
    $ret =~ s/\.0+([BMK])$/$1/;
    return $ret;
}

sub google2 {
    my( $site, $search ) = @_;
    my $url =   'http://ajax.googleapis.com/ajax/services/search/web?v=1.0&rsz=8' .
                "&q=$search&as_sitesearch=$site&gl=ca";

    my( $c, %ret );
    $_ = download( $url, 1 );
    $ret{'rstatus'} = /"responseStatus": (\d+)/ ? $1 : 0;
    foreach( /\{(.*?)\}/sg ) {
        next unless( /"url":"([^"]+)/ );
        $c++;
        $ret{'url'}[$c] = $1;
        ($ret{'title'}[$c]) = /"titleNoFormatting":"([^"]+)/;
        foreach( $ret{'url'}[$c], $ret{'title'}[$c] ) {
            s/\%([0-9A-F]{2})/chr hex $1/ge;
        }
        #print "Google: $c. $ret{'url'}[$c] ($ret{'title'}[$c]\n" if( DEBUG );
    }
    $ret{'count'} = $c ? $c : 0;
    print "Google found $ret{'count'} results.\n" if( DEBUG );
    return %ret;
} #Google

sub google {
    #https://www.googleapis.com/customsearch/v1?siteSearch=sports.yahoo.com&q=kessel&cx=007775933910534252983:d3pxxu8-ul4&key=AIzaSyBzq7JCfoRml_m7hKndjh7_Y6K1o1ANDO0&num=5
    my( $site, $search ) = @_;
    my $url =   'https://www.googleapis.com/customsearch/v1?num=8' .
                "&q=$search&siteSearch=$site&cx=007775933910534252983:d3pxxu8-ul4&key=AIzaSyBzq7JCfoRml_m7hKndjh7_Y6K1o1ANDO0";

    my( $c, %ret, $js );
    $_ = download( $url, 1 );

    eval { $js = decode_json( $_ ) };
    return google2( $site, $search ) if( $@ );

    my $items = $js->{items};
    foreach( @$items ) {
        #next if( $_->{'kind'} ne 'customsearch#result' );
        $c++;
        $ret{'title'}[$c] = $_->{title};
        $ret{'url'}[$c] = $_->{link};
        print "Google: $c. $ret{'url'}[$c] ($ret{'title'}[$c])\n" if( DEBUG );
    }
    if( !$c && $js->{'spelling'}{'correctedQuery'} ) {
        print "Google found spelling correction: $js->{spelling}{correctedQuery}\n" if( DEBUG );
        return google( $site, $1 ) if( $js->{'spelling'}{'correctedQuery'} =~ /(.*?) site:/ );
    }
    $ret{count} = $c ? $c : 0;
    #print "Google found $ret{'count'} results.\n" if( DEBUG );
    print "Google found nothing: " . Dumper($js) if( DEBUG && !$c );
    return %ret;
} #Google

sub simplejson {
    my( $json, %ret ) = ( shift, () );
    while( $json =~ /"(?<k>.*?)":(?:"(?<v>)"|"(?<v>.*?[^\\])"|(?<v>\[.*?\])|(?<v>.*?)(?:,|\}|$))/sg ) {
        my( $key, $value ) = ( $+{k}, $+{v} );
        $key =~ s/[^a-zA-Z0-9_]/_/g;
        $value =~ s/\\"/"/g;
        $ret{lc $key} = $value;
        #print "$key: $value\n" if( DEBUG );
    }
    return %ret;
}

sub CVI { #string to int
    $_ = shift;
    return 0 if( length($_) < 4 );
    my $i = 0;
    for my $c ( 0 .. 3 ) {
        my $s = substr( $_, $c, 1 );
        $i |= ord($s) << (8 * $c);
    }
    return $i;
}
