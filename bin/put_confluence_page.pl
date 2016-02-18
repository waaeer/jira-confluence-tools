#!/usr/bin/perl
use LWP;
use Getopt::Long;
use Pod::Usage;
use Term::ReadPassword;  # debian: libterm-readpassword-perl	
use JSON::XS;
use Data::Dumper;
use Encode;

use common::sense;

my ( $opt_verbose, $opt_help , $opt_id, $opt_home ,$opt_title, $opt_parent );

my $opt_user = $ENV{CONFLUENCE_USER};
my $opt_home = "";


GetOptions (
         "user=s"	=> \$opt_user,
         "verbose"  => \$opt_verbose,  
		 "id=s"	    => \$opt_id,
		 "title=s"  => \$opt_title,
		 "parent=i" => \$opt_parent,
		 "url=s"    => \$opt_home,
         "help"     => \$opt_help) or pod2usage(-verbose=>1);

            

$opt_help          && pod2usage(-verbose=>1);
$opt_id || pod2usage(-verbose=>1, -msg=>'Missing document id');	

my $passwd = read_password("JIRA password for $opt_user: "); 

binmode STDIN, ':utf8';
undef $/;
my $text = <STDIN>;

my $url = "$opt_home/rest/api/content/$opt_id";
my $res = request(GET=>"$url?expand=version,container,ancestors");
if(!$res->is_success) { 
    die("Failed to GET $url ($opt_user,******): ".$res->status_line);
}

my $content = decode_json($res->content);
my $version = $content->{version}->{number};
my $parent = $opt_parent || $content->{ancestors}->[-1]->{id};

my $cmd = { 
	version => { number=> $version+1 },
	($opt_title ? (	title => Encode::decode_utf8( $opt_title )) : (title => $content->{title})),
	ancestors => [{id => $parent }],
	type => 'page',
	body => {
		storage => { value => $text , representation => 'storage'},
	}
};

$res = request(PUT=>$url, $cmd);

if($res->is_success) { 
	my $content = decode_json($res->content);
	warn "Saved version $content->{version}->{number}\n";
} else { 
    die("Failed to PUT $url ($opt_user,******): ".$res->status_line);
}     	

exit(0);

sub request { 
	my ($method, $url, $json) = @_;
	my $req = HTTP::Request->new($method=>$url);
	$req->protocol('HTTP/1.1');
	$req->header('Content-type', 'application/json');
	$req->authorization_basic($opt_user, $passwd);
	if($method eq "PUT") { 
		$req->content(encode_json($json));
	}
	return LWP::UserAgent->new->request($req);
}

                               
__END__

=head1 NAME

put_confluence_page.pl - update a page in Atlassian Confluence

=head1 SYNOPSIS

perl put_confluence_page.pl --url  <Confluence base url> --user <user> --id <document_id> < FILE.html

=head1 DESCRIPTION


Page content is taken from STDIN. Can only update the body of existing Confluence page.

=head1 OPTIONS


=over 2 

=item --url : Confluence base URL, i.e. http://confluence.your.company.org

=item --user : username to login

=item -v : verbose operation

=item --title: Page title (if you want to change it)

=item --parent: Parent page id (if you want to change it)

=back




=cut


