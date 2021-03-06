#!/usr/bin/env perl

=head1 NAME

load_phage_finder.pl - Loads phage finder tab delimited output to sgc schema databases

=head1 SYNOPSIS

USAGE: load_phage_finder.pl
           --input_file
           --datatbase
           --bcp_out_dir
           --password_file
           --ergatis_to_sgc_lookup
        [  --no_load
           --log
           --debug
           --help  ]

=head1 OPTIONS

B<--input_file,-i>
    REQUIRED.  Tab delimited output file from phage finder run

B<--database,-d>
    REQUIRED.  Database to gather information from.  If bcp_out_dir is
    not specified, will load data to database automatically.

B<--bcp_out_dir,-b>
    REQUIRED.  Directory to write bcp files to.

B<--password_file,-p>
    REQUIRED. Tab delimited file containing username and password to 
    access the specified database.

    Ex. 
    username    password

B<--ergatis_to_sgc_lookup,-e>
    REQUIRED.  Since ergatis has requirements for feature ids, this may require the
    changing of some ids to run it through ergatis.  This will allow a map of
    temporary ergatis ids to ids specified in the sgc database.  Format is ergatis
    id followed by the corresponding sgc id separated by a tab.

    Ex.
    ergatis.polypeptide.12    SGC_000354
    ergatis.assembly.1        SGC_000023

B<--no_load,-n>
    OPTIONAL.  Flag.  Non-zero value will result in not loading the database.  Will
    only create bcp files that can be used to load the data later. If not specified,
    script will load.

B<--log,-l>
    OPTIONAL. Logfile. If no logfile is specified, prints logging 
    information to STDOUT

B<--help,-h>
    Print this message

=head1  DESCRIPTION

    This script is used to load ( or create bcp files for the loading of ) data
    generated by phage_finder.  Specifically, it was designed to load the tab
    delimited output of /usr/local/devel/ANNOTATION/phage_finder/bin/phage_finder_ergatis.pl.
    Other versions of phage_finder have not been tested.

=head1  INPUT
    
    --input_file
    
    Input to this script is the tab delimited output of phage_finder_ergatis.pl.
    
    Ex.
    PKT2440.assembly.1	6181863	61.52	1738082	1776894	38813	Large	degenerate	N.D.	N.D.	N.D.	61.18	pseudo_D3	PKT2440.polypeptide.1961	PKT2440.polypeptide.4239	0	0	0	0	0	0	+	0	0	0

    for format description, see phage_finder_ergatis.pl or Derrick Fouts (dfouts@jcvi.org)

    --password_file

    This file should contain one line, a username and password separated by a tab.  
    These are used to access the database.

    --ergatis_to_sgc_lookup
    
    Tab delimited, multi-line file representing of a map of ergatis_ids used to 
    the corresponding sgc ids.  Using the example above, a document might look
    like this:

    Ex.
    PKT2440.assembly.1    1
    PKT2440.polypeptide.1961    ?????????????


=head1 OUTPUT

    If the --bcp_out_dir is specfied, no data is loaded into
    the specfied database (but data is read from database). 

    Instead, bcp files are stored in the --bcp_out_dir to
    be loaded later if necesary.  The format of bcp files is
    as follows:

    *** MORE INFORMATION TO FOLLOW ****
    not quite sure where the data is going yet.


=head1  CONTACT

    Kevin Galens
    kgalens@tigr.org

=cut

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use Pod::Usage;
use DBI;
use Data::Dumper;

####### GLOBALS AND CONSTANTS ###########
my $input_file = "";
my $data = {};
my %options = ();
my $load = 1;
my $bcp_out_dir;                  
my $ergatis_to_sgc = {};
my $database;
my ($user,$pass);
my $log_h;                        #Log file handle
########################################

my $results = GetOptions (\%options, 
                          'input_file|i=s',
                          'database|d=s',
                          'bcp_out_dir|b=s',
                          'password_file|p=s',
                          'ergatis_to_sgc_lookup|e=s',
                          'no_load|n=s',
                          'log|l=s',
                          'help|h') || &_pod;

#Check options
&check_parameters( \%options );

#Parse data from input file
$data = &parse_phage_finder_data( $input_file );

#Check the ids
&check_ids( $data );

#Print the bcp files
my $bcp_files = &print_bcp( $bcp_out_dir, $data );

if( $load ) {

    &load_data( $bcp_files );

}


####################### SUB ROUTINES ##################################
#Name:  print_bcp
#Desc:  creates bcp files in specified bcp output directory
#Args:  bcp output directory, data structure returned from
#       parse_phage_finder_data
#Rets:  Nothing
sub print_bcp {
    my ($bcp_out_dir, $data) = @_;

    #This will create bcp files.  Delimiter will be 
    #something I don't know yet.

    #Feat_type phage
    my $asm_feature_bcp_file = "$bcp_out_dir/asm_feature.out.bcp";
    my $ident_bcp_file = "$bcp_out_dir/ident.out.bcp";
    my $feat_link_bcp_file = "$bcp_out_dir/feat_link.out.bcp";

    #Get the start feat_name
    my $dbh = &connect_to_database( $user, $pass );
    $dbh->do("use $database");

    open( ASM, "> $asm_feature_bcp_file" ) or
        die("Unable to open $asm_feature_bcp_file for writing ($!)");
    open( IDE, "> $ident_bcp_file" ) or
        die("Unable to open $ident_bcp_file for writing ($!)");
    open( FEL, "> $feat_link_bcp_file" ) or
        die("Unable to open $feat_link_bcp_file for writing ($!)");

    foreach my $asmbl_id ( keys %{$data} ) {

        my $max_num = &get_max_feat_num( $dbh, $ergatis_to_sgc->{$asmbl_id}, 'phage' );
        print "Max_num: $max_num\n";

        foreach my $data_row ( @{$data->{$asmbl_id}} ) {
    
            $max_num++;
            my $feat_name = "PHAGE".$max_num;

            #There are 17 columns in asm_feature
            my @row = ( '1',           #feat_id placeholder
                        "phage",       #feat_type
                        '',            #feat_class
                        "phage_finder_ergatis",   #feat_method
                        $data_row->{'end5'},
                        $data_row->{'end3'},
                        "phage_finder_ergatis",   #comment
                        $user,                    #assignby
                        '',
                        '','',
                        $feat_name,
                        '',
                        $ergatis_to_sgc->{$asmbl_id},
                        '',
                        '1',
                        '0','' );

            my $asm_line = join( "\t", @row );
            print ASM $asm_line."\n";

            #There are 16 columns in ident
            @row = ( $feat_name,
                     '',
                     $data_row->{'com_name'},
                     "from: ".$data_row->{'from'},
                     $user,
                     '',
                     '','','','','','',
                     '0','','','' );

            my $ident_line = join( "\t", @row );
            print IDE $ident_line."\n";

            foreach my $gene ( @{$data_row->{'genes'}} ) {

                #Now we need feat_link
                @row = ( '1',
                         $feat_name,
                         $ergatis_to_sgc->{$gene},
                         $user,'' );

                my $feat_link_line = join( "\t", @row );
                print FEL $feat_link_line."\n";
            }       
        }
    }

    close( ASM );
    close( IDE );
    close( FEL );

    return { 'asm_feature' => $asm_feature_bcp_file,
             'ident'       => $ident_bcp_file,
             'feat_link'   => $feat_link_bcp_file };
             

}

#Name:  get_max_feat_num
#Desc:  Searches the asm_feature table with given db handle
#       and returns the maximum number for a given feat_type.
#Args:  Opened database handle, assembly id, and feature type
#Rets:  The maximum number used in the database currently
sub get_max_feat_num {
   my ($dbproc, $asmbl_id, $feat_type) = @_;

   my $num = 0;
   my $query = "SELECT feat_name "
       . "FROM asm_feature "
       . "WHERE asmbl_id = $asmbl_id "
       . "AND feat_type = \'$feat_type\' ";

   my $sth = $dbproc->prepare( $query );
   $sth->execute();
   print "Executing:\n[$query]\n";
   
   my $array_ref = $sth->fetchall_arrayref();

   my @values = map( { return $1 if( $_->[0] =~ /\D(\d+)$/) }  @{$array_ref} ); 

   if( @values < 1 ) {
       return "00000";
   } else {
       my @sorted_values = sort @values;       
       return pop @values;
   }

} 

#Name:  load_data
#Desc:  loads the data directly to the database
#Args:  the data structure output from parse_phage_finder_data
#Rets:  nothing
sub load_data {
    my $bcp_files = shift;

    while( my ($table, $file) = each( %{$bcp_files} ) ) {
        my $cmd = "bcp $database..$table in $file -t \"\\t\" -U $user -P $pass -c";
        print "\n$cmd\n";
        system( $cmd );

        my $ret_val = $? >> 8;
        print "Return Value: $ret_val\n";

        die("bcp command failed.  Please correct error and rerun") unless( $ret_val == 0 );
    }
 
}

#Name:  check_ids
#Desc:  checks the ids parsed from the phage_finder output
#       against those found in the database.
#Args:  Data structure returned from parse_phage_finder_data
#Rets:  Nothing.  Dies if it cannot find a parsed id in the database
sub check_ids {
    my $data = shift;

    my $database_ids = {};

    my $dbh = &connect_to_database( $user, $pass );
    $dbh->do("use $database");

    #Retrieve all the gene ids
    my ($asmbl_id,$feat_name);

    my $query = 
        "SELECT af.feat_name, af.asmbl_id ".
        "FROM asm_feature af, stan s ".
        "WHERE s.iscurrent = 1 ".
        "AND s.asmbl_id = af.asmbl_id ".
        "AND af.feat_type = \"ORF\"";

    my $sth = $dbh->prepare( $query );

    $sth->execute();

    $sth->bind_columns(undef, \$feat_name, \$asmbl_id);

    while( $sth->fetch() ) {
        $database_ids->{$feat_name} = $asmbl_id;
    }

    #Cycle through all the ids in data and make sure
    #that we don't have a parsed id that isn't contained within
    #the $database_ids data structure.  Also make sure
    #they are located on the correct assembly.
    foreach my $parsed_asmbl ( keys %{$data} ) {

        foreach my $parsed_feat (  @{$data->{$parsed_asmbl}} ) {

            foreach my $gene ( @{$parsed_feat->{'genes'}} ) {
                die("Could not find $gene in ergatis_to_sgc_lookup") 
                    unless( exists( $ergatis_to_sgc->{$gene} ) );
                my $sgd_id = $ergatis_to_sgc->{$gene};
                
                die("Could not find $sgd_id in database")
                    unless( exists( $database_ids->{$sgd_id} ) );

                die("$sgd_id ( ergatis: $gene ) located on different assembly than ".
                    "in database. (phage_finder out: $gene :: database: $database_ids->{$sgd_id}")
                    unless( $ergatis_to_sgc->{$parsed_asmbl} eq $database_ids->{$sgd_id} );

            }
        }
    }
    

}

#Name:  conntect_to_database
#Desc:  creates a DBI connection to sybase database using 
#       specific username and password
#Args:  username and password
#Rets:  DBI database handle
sub connect_to_database {
    my ($user, $pass) = @_;

    my $retval = DBI->connect('dbi:Sybase:server=SYBTIGR; packetSize=8092', $user, $pass)
        or die("Unable to connect to database".${DBI->errstr});

    return $retval;
}

#Name:  parse_phage_finder_data
#Desc:  Parses the output of phage_finder_ergatis into a data structure.
#Args:  A tab delimited output file from phage_finder.
#Rets:  A data structure in the format:
#
sub parse_phage_finder_data {
    my $file = shift;
    my $retval = {};

    open( IN, "< $file" ) or 
        die("Unable to open $file ($!)");

    my $asmbl_id;

    while( my $line = <IN> ) {
        my @cols = split( /\t/, $line );

        $asmbl_id = $cols[0];

        my $num_cols = scalar( @cols );
        my @tmp = @cols[13..($num_cols-11)];
        die("there were no genes associated with this phage") if( @tmp < 1 );

        my $genes = \@tmp;
        push( @{$retval->{$asmbl_id}}, { 'end5'     => $cols[3],
                                          'end3'     => $cols[4],
                                          'com_name' => $cols[6]." ".$cols[7],
                                          'from'     => $cols[12],
                                          'genes'    => $genes } );
        
    }

    return $retval;
}

#Name:  make_ergatis_to_sgc_lookup 
#Desc:  Creates a hash of ergatis id -> sgc ids from file.
#Args:  Input file in format:
#       ergatis_id\tsgc_id
#Rets:  Reference to a hash with key = ergatis_id
#                              value = sgc_id
sub make_ergatis_to_sgc_lookup {
    my $file = shift;
    my $retval = {};

    open( IN, "< $file" ) or 
        die("Could not open $file ($!)");

    while( my $line = <IN> ) {
        chomp( $line );
        my ($k,$v) = split(/\s+/, $line);
        $retval->{$k} = $v;
    }

    close(IN);

    print $log_h "Found ".scalar( keys %{$retval} )." id sets in lookup file\n";

    return $retval;
}


#Checks options and dies on input error.
sub check_parameters {
    my $opts = shift;

    #Set up the log first
    if( $opts->{'log'} ) {
        open( $log_h, "< $opts->{'log'}" ) or 
            die("Can't open $opts->{'log'} ($!)");
    } else {
        $log_h = *STDOUT;
    }

    #--input_file is required
    if( $opts->{'input_file'} ) {
        $input_file = $opts->{'input_file'};
        die("option --input_file [$input_file] does not exist")
            unless( -e $input_file );
    } else {
        die("option --input_file is required");
    }

    #--database is required 
    if( $opts->{'database'} ) {
        $database = $opts->{'database'};
    } else {
        die("option --database is required");
    }

    #--bcp_out_dir
    if( $opts->{'bcp_out_dir'} ) {
        $bcp_out_dir = $opts->{'bcp_out_dir'};
    } else {
        die("option --bcp_out_dir is required");
    }

    #--no_load
    if( $opts->{'no_load'} ) {
        $load = 0;
    } else {
        $load = 1;
    }

    #--password_file is required
    if( $opts->{'password_file'} ) {
        open(PW, "< $opts->{'password_file'}") or
            die("Unable to open $opts->{'password_file'} ($!)");
        chomp (($user,$pass) = <PW>);
        die("Password file [$opts->{'password_file'}] in unexpected format.  See ".
            "documentation") unless( $user && $pass );
    } else {
        die("option --password_file is required");
    }

    #--ergatis_to_sgc_lookup is optional
    if( $opts->{'ergatis_to_sgc_lookup'} ) {
        $ergatis_to_sgc = &make_ergatis_to_sgc_lookup( $opts->{'ergatis_to_sgc_lookup'} );
    } else {
        $ergatis_to_sgc = {};
    }

}

#Displays perl documentation and exits.
sub _pod {
    pod2usage( {-exitval => 0, -verbose => 2, -output => \*STDERR} );
}


