#!/usr/bin/perl
use LWP;
use Getopt::Long;
use Pod::Usage;
use Term::ReadPassword;  # debian: libterm-readpassword-perl	
use XML::LibXML;
use Data::Dumper;

use common::sense;

my ( $opt_verbose, $opt_help , $opt_id);

my $opt_user = $ENV{CONFLUENCE_USER};
my $opt_home = "";


GetOptions (
         "user=s"	=> \$opt_user,
         "verbose"  => \$opt_verbose,  
		 "id=s"	    => \$opt_id,
		 "url=s"    => \$opt_home,
         "help"     => \$opt_help) or pod2usage(-verbose=>1);

            
my ($space,$name) = @ARGV;

$opt_help          && pod2usage(-verbose=>1);
$opt_id || ($space && $name ) || pod2usage(-verbose=>1, -msg=>'Missing id, name and/or space');	

my $passwd = read_password("JIRA password for $opt_user: "); 

my $src = $opt_id ? get_confluence_page(id=>$opt_id) : get_confluence_page(space=>$space, name=>$name);
print $src;
exit(0);

sub get_confluence_page {  ### Получает из Confluence страницу (два варианта вызова - id или space+name) 
        my %opt = @_;
        my $url;
        warn "get confluence page", Dumper(\%opt) if $opt_verbose;
        if( $opt{id} ) { 
        	$url = "$opt_home/rest/prototype/1/content/$opt{id}";
        } elsif ($opt{space} && $opt{name}) { 
            my $name = $opt{name};
            $name =~ s/ /+/g;
            $url = "$opt_home/display/$opt{space}/$name";
            my $view_page = get_page($url);
            warn "page $url got" if $opt_verbose;
            if($view_page !~ m!<meta name="ajs-page-id" content="(\d+)">!) { 
                     die("cannot find ajs-page in $url");
            }
            $url = "$opt_home/rest/prototype/1/content/$1"; 
            warn "Looking at $url" if $opt_verbose;
        } else { 
        	die("strange args for get_confluence_page", Dumper(\%opt));
        }
        my $page = get_page($url);
        print $page,"\n--------------------------------\n" if $opt_verbose;
        my $xml = XML::LibXML->load_xml(string=>$page);
        my $xpc = XML::LibXML::XPathContext->new;
        my $content = $xpc->find('//body/text()', $xml)->[0]->data;
        print $content,"\n------------------------------\n" if $opt_verbose;

		return $content;
}
         

###############################################################################################


sub get_page {    ### получает произвольную страницу из JIRA и Confluence в виде HTML
        my ($url)= @_;
       
        my $req = HTTP::Request->new(GET=>$url);
        $req->authorization_basic($opt_user, $passwd);
        my $res = LWP::UserAgent->new->request($req);
        if($res->is_success) { 
                return $res->content;
        } else { 
                die("Failed to request $url ($opt_user,******): ".$res->status_line);
        }     	
}               
                               
__END__

=head1 NAME

get_confluence_page.pl - extract page from Atlassian confluence

=head1 SYNOPSIS

perl get_confluence_page.pl --url <Confluence base url> --user <user> <space name> <document name>

or 

perl get_confluence_page.pl --url  <Confluence base url> --user <user> --id <document_id>


=head1 OPTIONS

=over 2 

=item --url : Confluence base URL, i.e. http://confluence.your.company.org

=item --user : username to login

=item -v : verbose operation

=back




=cut


