#!/usr/bin/perl

use LWP;
use Getopt::Long;
use Pod::Usage;
use Term::ReadPassword;  # debian: libterm-readpassword-perl	
use XML::LibXML;
use Data::Dumper;
use File::Temp qw(tempdir);
use JIRA::Client::Automated;
use MIME::Parser;
use Encode;

use common::sense;

my ( $opt_verbose, $opt_help , $opt_project, $opt_real);

my $opt_user = $ENV{JIRA_USER};
my $opt_jira;

GetOptions (
         "user=s"	=> \$opt_user,
         "verbose"  => \$opt_verbose,  
		 "project=s"=> \$opt_project,
		 "jira=s"   => \$opt_jira,
		 "real"     => \$opt_real,
         "help"     => \$opt_help) or pod2usage(-verbose=>1);

$opt_help          && pod2usage(-verbose=>1);

## Разбираем письмо из входного потока

my $parser = new MIME::Parser;
my $tmpdir = tempdir(CLEANUP=>1);

$parser->output_under($tmpdir);
my $entity = $parser->parse(\*STDIN);



### Congratulations: you now have a (possibly multipart) MIME entity!
$entity->dump_skeleton;          # for debugging

my $data = { 
	subject => Encode::decode('MIME-Header', $entity->head->get('subject')),
	files   => [],
};

process_entity($entity, $data);


if($opt_real) { 
	$opt_project || pod2usage(-verbose=>1, -msg=>'Missing project key');	
	$opt_jira    || pod2usage(-verbose=>1, -msg=>'Missing jira url');	

	my $passwd = read_password("JIRA password for $opt_user: "); 
	my $jira = JIRA::Client::Automated->new($opt_jira, $opt_user, $passwd);
	my $text = Encode::decode('utf8',$data->{text});
	if ($data->{format} eq 'html') { 
		$text = '{html}'.$text.'{html}';
	}
	my $issue = $jira->create({
            project     => {
                key => $opt_project,
            },
            issuetype   => {
                name => "Task", # $type,      # "Bug", "Task", "Sub-task", etc.
            },
            summary     => $data->{subject},
            description => $text,
        });
warn Data::Dumper::Dumper($issue);

	foreach my $f (@{$data->{files}}) { 
		$jira->attach_file_to_issue($issue->{key}, $f);
	}

}

warn Dumper($data);

exit(0);

sub process_entity { 
	my ($ent, $data) = @_;
	my $h = $ent->head;
	my $ct = $h->mime_type;
#	warn "Ct: $ct\n";
	if($ct eq 'multipart/mixed') { 
		warn "(\n";	
		my $n_parts = $ent->parts;
		for(my $i=0;$i<$n_parts;$i++) { 
			process_entity( $ent->parts($i), $data );
		}
		warn ")\n";	
	} elsif ($ct eq 'multipart/alternative') { 
		my $n_parts = $ent->parts;
		my $best_part;
		for(my $i=0;$i<$n_parts;$i++) { 
			my $part = $ent->parts($i);
			my $mime_type = $part->head->mime_type;
			if ( $mime_type eq 'text/plain') {
				$best_part ||= $part;
			} elsif ( $mime_type eq 'text/html') {
# For JIRA, ignore HTML :(
				$best_part = $part;
			} else { 
				die("Unexpected mime type $mime_type in alternative ", $entity->dump_skeleton);
			}
		}
		warn "[\n";
		process_entity( $best_part , $data );
		warn "]\n";
		
	} elsif ( $ct =~ m|^text/(.*)$| ) { 
		my $format = $1;
		my $body = $ent->bodyhandle;
		$data->{text} = $body->as_string;
		$data->{format} = $format;
	} else { 
		my $disp = $ent->head->mime_attr('content-disposition');
		if($disp eq 'attachment') { 
			my $fn   = $ent->head->recommended_filename();
			my $path = $ent->bodyhandle->path;
			if($path) { 
				push @{ $data->{files} }, $path;
				warn "-------- disp: ",$disp," n=$fn p=$path\n"; # . $ent->head->as_string,"\n";
			} else { 
				die("No path for ".$ent->head->as_string."\n");
			}
		} else { 
			die("Non attached file");
		}
	}


}
