package Ergatis::ConfigFile;

=head1 NAME

Ergatis::ConfigFile.pm - A class for parsing ergatis config files.

=head1 SYNOPSIS

    use Ergatis::ConfigFile;

    my $conf = Ergatis::ConfigFile->new( -file => $conf_file );

    ## replace variables.
    $conf = $conf->import_includes();
    $conf = $conf->replace_variables();
    
    ## all other methods inherited from Config::IniFiles
    
=head1 DESCRIPTION

This class is a subclass of Config::IniFiles, and adds the ability to import 
include files (like sharedconf.ini) and do variable replacement.

=head1 METHODS

=over 3

=item I<PACKAGE>->new( file => I<'/path/to/some.ini'> )

Returns a newly created "Ergatis::ConfigFile" object.

=item I<$OBJ>->import_includes( )

Imports any include files referenced within the ini file.  The include itself is
not currently removed, though perhaps it should be.  I only chose to leave it
so we would have a reference of which file was included (and because the old
version of this did so.)  This method returns the version of the conf file
containing the imports.

=item I<$OBJ>->replace_variables( )

Scans through the conf file looking for any variables ( like $;FOO$; ) which can
be resolved internally and substitutes the intended values.  Any includes should
be performed before this method is called.  This method returns the version of the 
conf file containing the imports.

=back

=head1 AUTHOR

    Joshua Orvis
    jorvis@tigr.org

=cut

use strict;
use Carp;
use Digest::MD5 qw(md5_hex);
use base qw(Config::IniFiles);


## does not delete the included variables (maybe it should.)
sub import_includes {
    my $self = shift;
    
    for my $include_section ( $self->GroupMembers('include') ) {

        for my $param ( $self->Parameters( $include_section ) ) {
            my $path = $self->val( $include_section, $param );
            
            if ( -e $path ) {
                my $include = new Ergatis::ConfigFile( 
                                    -file => $path,
                                    -import => $self,
                              );
                $self = $include;
            }
        }
    }
    
    return $self;
}

sub project_list_md5 {
    my $self = shift;
    my $seed = '';
    
    ## build an md5 from the sorted version of the project list
    for my $label ( sort $self->Parameters( 'projects' ) ) {
        $seed .= "$label," . $self->val('projects', $label);
    }
    
    return md5_hex($seed);
}

sub replace_variables {
    my $self = shift;

    my $allkeys = {};
    my $checkvalues = {};
    
    for my $section ( $self->Sections() ) {

        for my $param ( $self->Parameters( $section ) ) {
            my $value = $self->val( $section, $param );
            
            ## take spaces off front and back of value, leaving internal ones
            $value =~ s/^\s*(.+?)\s*$/$1/;
            
            $self->setval($section, $param, $value);
            $allkeys->{$param}->{'value'} = $value;
            $allkeys->{$param}->{'section'} = $section;
            
            if ($value =~ /\$;[\w_]+\$;/){
                $checkvalues->{$param} = $value;
            }
        }
    }

    for my $key ( keys %{$checkvalues} ) {
        my $value = $checkvalues->{$key};
        
        while ( _check_value($value, $allkeys) ) {
            $value =~ s/(\$;[\w_]+\$;)/&_replace_value($1,$allkeys)/ge;
        }
        
        my $setval = $self->setval($allkeys->{$key}->{'section'},$key,$value);
        
        if (! $setval) {
            croak("key $key in section $allkeys->{$key}->{'section'} is not valid");
        }
    }

    return $self;    
}

sub _replace_value {
    my ($val, $keylookup) = @_;
    
    if (! (exists $keylookup->{$val}) ){
        croak("Bad key $1 in configuration file");
        
    } elsif ( $keylookup->{$val}->{'value'} eq '') {
        return $val;
        
    } else {
        return $keylookup->{$val}->{'value'};
    }
}

sub _check_value {
    my ($val, $keylookup) = @_;
    
    if ( $val =~ /\$;[\w_]+\$;/ ) {
        my ($lookupval) = ($val =~ /(\$;[\w_]+\$;)/); 

        if( $keylookup->{$lookupval}->{'value'} eq "" ){
            return 0;
        } else {
            return 1;
        }
    }
}

1==1;

