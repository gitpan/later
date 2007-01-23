#
#   $Id: later.pm,v 1.7 2007/01/23 16:05:12 erwan Exp $
#
#   postpone using a module until it is needed at runtime
#
#   2007-01-09 erwan First version
#   2007-01-22 erwan Support import arguments and object orientation
#   2007-01-23 erwan Support recursive 'use later' calls
#

package later;

use strict;
use warnings;
use Symbol;
use Data::Dumper;
use Carp qw(croak);

our $VERSION = '0.01';

#--------------------------------------------------------------------
#
# '%modules' has the following structure:
#  
#             # name of the package doing 'use later'
# %modules = ( 'caller_package' => { 
#                                    # module to be imported in the caller_package, and with which import arguments
#                                    'module_1' => [ @import_arguments ],
#                                    'module_2' => [ @import_arguments ],
#                                    ...
#                                  }
# 

my %modules;

#--------------------------------------------------------------------
#
#   import - store the name and import arguments of a module to
#            import later on in the caller package
#

sub import {
    my $self = shift @_;
    my $caller = caller(0);
    my $latered = shift @_;

    croak "'use later' must be followed by a module name and eventual import arguments" if (!defined $latered);

    # NOTE: should we check that the $latered module exists? -> no: enable on the fly generation of modules...
    # NOTE: if the caller package or the delayed package define an AUTOLOAD of their own, we will have a conflict...

    # add an AUTOLOAD to the caller module
    if (!exists $modules{$caller}) {
	$modules{$caller} = {};
	*{ qualify_to_ref('AUTOLOAD',$caller) } = *{ qualify_to_ref('_autoload','later') };
    }

    $modules{$caller}->{$latered} = \@_;

    # add an AUTOLOAD even to the postponed module, to handle full name calls (ex: My::Module::foo() )
    *{ qualify_to_ref('AUTOLOAD',$latered) } = *{ qualify_to_ref('_autoload','later') };
}

#--------------------------------------------------------------------
#
#   _autoload - act as the caller package's AUTOLOAD. does a number
#               of 'use $module' and call the undefined sub if it now defined
#               otherwise die
#

sub _autoload {

    # looking up a missing DESTROY sub is ok...
    return if ($later::AUTOLOAD =~ /::DESTROY$/); 

    my ($pkg,$filename,$line) = caller;

    # do a 'use module' on each postponed module inside the caller's package
    if (exists $modules{$pkg})  {
	foreach my $module (keys %{$modules{$pkg}}) {
	    _use_module($pkg,$module,@{$modules{$pkg}->{$module}});
	    delete $modules{$pkg}->{$module};
	}
    }

    # if the originally undefined sub is now available, call it
    if ($pkg->can($later::AUTOLOAD)) {
	goto &$later::AUTOLOAD;
    } 
    
    # sub is still undefined. let's die...
    die "Undefined subroutine &$later::AUTOLOAD called at $filename line $line\n";
}

#--------------------------------------------------------------------
#
#   _use_module - use a module with the right parameters
#

sub _use_module {
    my ($caller,$module,@args) = @_;

    # the main issue with the delayed 'eval "package; use *"' method is how
    # to pass import arguments to the used module. I unfortunately didn't 
    # find any better way than converting them to a string with Data::Dumper. 
    # ugly. does not keep coderefs passed as import arguments...

    # change Data::Dumper indentation temporarily
    my $indent = $Data::Dumper::Indent;
    $Data::Dumper::Indent = 0;

    my $str = "";
    if (@args) {
	$str = Dumper(\@args);
	$str =~ s/^\$VAR1 = \[(.*)\];[\n\r]*$/$1/mg 
	    || croak "use later: Failed to parse import arguments for module $module inside package $caller. Arguments are: $str";
    }
    $Data::Dumper::Indent = $indent;

    # now use the delayed module
    eval "package $caller; use $module $str;";
    if ($@) {
	croak "use later: Failed to use package $module inside package $caller.\nEval says: $@";
    }
}

1;

__END__

=head1 NAME

later - A pragma to postpone using a module

=head1 SYNOPSIS

Assuming we have a module Foo exporting the function bar():

    package Foo;
    
    use base qw(Exporter);
    our @EXPORT_OK = qw(bar);

    sub bar {
	# do whatever
    }

    1;

And somewhere else we use Foo and call bar():

    use Foo qw(bar);
     
    bar('some','arguments');

Now, for a number of possibly rather unsane reasons you might want
to delay actually evaling 'use Foo' until I<bar> is called at runtime. 
To do that, change the former code into:

    use later 'Foo', qw(bar);

    bar('some','arguments');

This works even for object packages:

    use later 'My::Classy::Class';

    my $object = new My::Classy::Class;

And supports import arguments:

    use later 'My::Classy::Class', do_fuss => 1;

    my $object = new My::Classy::Class;



=head1 DESCRIPTION

The C<later> pragma enables you to postpone using
a module until its exported methods are needed during runtime.

=head1 API

=over 4

=item C<use later 'Module::Name';>

or 

=item C<< use later 'Module::Name', arg1 => $value1, ...; >>

Postpone C<use Module::Name> until an undefined subroutine is found
in the current package at runtime. Only when it happens shall
I<later> evaluate 'use I<Module::Name>' inside the current package, 
hence hopefully importing the undefined subroutine into the current
package's namespace. The formerly undefined subroutine is then called
as if nothing unusual had happened.

Any further encounter with an undefined subroutine will still result in the
standard 'Undefined subroutine' error.

If multiple modules are called with c<use later> inside the same package, 
they will all be used upon the first encounter with an undefined subroutine
in this package, despite the fact that only one of them should export the 
specific undefined subroutine.

If I<Module::Name> is called with import arguments, those will be passed
to the module when it is used. Note that the C<later> pragma does not support
passing code refs as import arguments.

You may C<use later> modules that C<use later> other modules (and so on recursively).
It will work.

Examples:

    use later 'Data::Dumper';

    # Data::Dumper is effectively used upon calling 'Dumper'
    print Dumper([1,2,3]);

or 

    use later 'MyLog', level => 1;
 
    # MyLog is used with the import parameters 'level => 1' upon calling 'mylog'
    mylog("some message");

Notice that when passing import arguments together with the module name,
you have to separate them from the module name with a comma ','.

=back

=head1 BUGS AND LIMITATIONS

This module is a proof of concept and does not support all 
possible use cases.

The C<later> pragma will not work properly if the calling
module has an AUTOLOAD function, since it will
conflict with the AUTOLOAD that C<later> silently injects
into both the calling module and the called module.

The C<later> pragma does not support passing code references
as import arguments to the used module.

Since postponed modules are searched for and compiled only
during runtime, any error in the module (compilation or other) is delayed
until then. You are therefore at risk of crashing your program in the middle
of its runtime due to errors that would normally be detected during compilation.

As far as I am concerned, I fail to see any sane situation where
this pragma would be needed that cannot be implemented in a safer
way without C<later>. You have been warned :)

Should you find other bugs or suggest changes, please send an email
to C<< <erwan@cpan.org> >>.

=head1 SEE ALSO

See 'load', 'SelfLoader', 'AutoLoader'.

=head1 VERSION

$Id: later.pm,v 1.7 2007/01/23 16:05:12 erwan Exp $

=head1 AUTHOR

Erwan Lemonnier C<< <erwan@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

This code is distributed under the same terms as Perl itself.

=head1 DISCLAIMER OF WARRANTY

This is free code and comes with no warranty. The author declines any personal 
responsibility regarding the use of this code or the consequences of its use.

=cut





