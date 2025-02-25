package autodie::Util;

use strict;
use warnings;

use Exporter 5.57 qw(import);

use autodie::Scope::GuardStack;

our @EXPORT_OK = qw(
  fill_protos
  install_subs
  make_core_trampoline
  on_end_of_compile_scope
);

our $VERSION = '2.31'; # VERSION: Generated by DZP::OurPkg:Version

# ABSTRACT: Internal Utility subroutines for autodie and Fatal

# docs says we should pick __PACKAGE__ /<whatever>
my $H_STACK_KEY = __PACKAGE__ . '/stack';

sub on_end_of_compile_scope {
    my ($hook) = @_;

    # Dark magic to have autodie work under 5.8
    # Copied from namespace::clean, that copied it from
    # autobox, that found it on an ancient scroll written
    # in blood.

    # This magic bit causes %^H to be lexically scoped.
    $^H |= 0x020000;

    my $stack = $^H{$H_STACK_KEY};
    if (not defined($stack)) {
        $stack = autodie::Scope::GuardStack->new;
        $^H{$H_STACK_KEY} = $stack;
    }

    $stack->push_hook($hook);
    return;
}

# This code is based on code from the original Fatal.  The "XXXX"
# remark is from the original code and its meaning is (sadly) unknown.
sub fill_protos {
    my ($proto) = @_;
    my ($n, $isref, @out, @out1, $seen_semi) = -1;
    if ($proto =~ m{^\s* (?: [;] \s*)? \@}x) {
        # prototype is entirely slurply - special case that does not
        # require any handling.
        return ([0, '@_']);
    }

    while ($proto =~ /\S/) {
        $n++;
        push(@out1,[$n,@out]) if $seen_semi;
        push(@out, $1 . "{\$_[$n]}"), next if $proto =~ s/^\s*\\([\@%\$\&])//;
        push(@out, "\$_[$n]"),        next if $proto =~ s/^\s*([_*\$&])//;
        push(@out, "\@_[$n..\$#_]"),  last if $proto =~ s/^\s*(;\s*)?\@//;
        $seen_semi = 1, $n--,         next if $proto =~ s/^\s*;//; # XXXX ????
        die "Internal error: Unknown prototype letters: \"$proto\"";
    }
    push(@out1,[$n+1,@out]);
    return @out1;
}


sub make_core_trampoline {
    my ($call, $pkg, $proto_str) = @_;
    my $trampoline_code = 'sub {';
    my $trampoline_sub;
    my @protos = fill_protos($proto_str);

    foreach my $proto (@protos) {
        local $" = ", ";    # So @args is formatted correctly.
        my ($count, @args) = @$proto;
        if (@args && $args[-1] =~ m/[@#]_/) {
            $trampoline_code .= qq/
                if (\@_ >= $count) {
                    return $call(@args);
                }
             /;
        } else {
            $trampoline_code .= qq<
                if (\@_ == $count) {
                    return $call(@args);
                }
             >;
        }
    }

    $trampoline_code .= qq< require Carp; Carp::croak("Internal error in Fatal/autodie.  Leak-guard failure"); } >;
    my $E;

    {
        local $@;
        $trampoline_sub = eval "package $pkg;\n $trampoline_code"; ## no critic
        $E = $@;
    }
    die "Internal error in Fatal/autodie: Leak-guard installation failure: $E"
        if $E;

    return $trampoline_sub;
}

# The code here is originally lifted from namespace::clean,
# by Robert "phaylon" Sedlacek.
#
# It's been redesigned after feedback from ikegami on perlmonks.
# See http://perlmonks.org/?node_id=693338 .  Ikegami rocks.
#
# Given a package, and hash of (subname => subref) pairs,
# we install the given subroutines into the package.  If
# a subref is undef, the subroutine is removed.  Otherwise
# it replaces any existing subs which were already there.

sub install_subs {
    my ($target_pkg, $subs_to_reinstate) = @_;

    my $pkg_sym = "${target_pkg}::";

    # It does not hurt to do this in a predictable order, and might help debugging.
    foreach my $sub_name (sort keys(%{$subs_to_reinstate})) {

        # We will repeatedly mess with stuff that strict "refs" does
        # not like.  So lets just disable it once for this entire
        # scope.
        no strict qw(refs);   ## no critic

        my $sub_ref = $subs_to_reinstate->{$sub_name};

        my $full_path = ${pkg_sym}.${sub_name};
        my $oldglob = *$full_path;

        # Nuke the old glob.
        delete($pkg_sym->{$sub_name});

        # For some reason this local *alias = *$full_path triggers an
        # "only used once" warning.  Not entirely sure why, but at
        # least it is easy to silence.
        no warnings qw(once);
        local *alias = *$full_path;
        use warnings qw(once);

        # Copy innocent bystanders back.  Note that we lose
        # formats; it seems that Perl versions up to 5.10.0
        # have a bug which causes copying formats to end up in
        # the scalar slot.  Thanks to Ben Morrow for spotting this.

        foreach my $slot (qw( SCALAR ARRAY HASH IO ) ) {
            next unless defined(*$oldglob{$slot});
            *alias = *$oldglob{$slot};
        }

        if ($sub_ref) {
            *$full_path = $sub_ref;
        }
    }

    return;
}

1;

__END__

=head1 NAME

autodie::Util - Internal Utility subroutines for autodie and Fatal

=head1 SYNOPSIS

    # INTERNAL API for autodie and Fatal only!

    use autodie::Util qw(on_end_of_compile_scope);
    on_end_of_compile_scope(sub { print "Hallo world\n"; });

=head1 DESCRIPTION

Interal Utilities for autodie and Fatal!  This module is not a part of
autodie's public API.

This module contains utility subroutines for abstracting away the
underlying magic of autodie and (ab)uses of C<%^H> to call subs at the
end of a (compile-time) scopes.

Note that due to how C<%^H> works, some of these utilities are only
useful during the compilation phase of a perl module and relies on the
internals of how perl handles references in C<%^H>.

=head2 Methods

=head3 on_end_of_compile_scope

  on_end_of_compile_scope(sub { print "Hallo world\n"; });

Will invoke a sub at the end of a (compile-time) scope.  The sub is
called once with no arguments.  Can be called multiple times (even in
the same "compile-time" scope) to install multiple subs.  Subs are
called in a "first-in-last-out"-order (FILO or "stack"-order).

=head3 fill_protos

  fill_protos('*$$;$@')

Given a Perl subroutine prototype, return a list of invocation
specifications.  Each specification is a listref, where the first
member is the (minimum) number of arguments for this invocation
specification.  The remaining arguments are a string representation of
how to pass the arguments correctly to a sub with the given prototype,
when called with the given number of arguments.

The specifications are returned in increasing order of arguments
starting at 0 (e.g.  ';$') or 1 (e.g.  '$@').  Note that if the
prototype is "slurpy" (e.g. ends with a "@"), the number of arguments
for the last specification is a "minimum" number rather than an exact
number.  This can be detected by the last member of the last
specification matching m/[@#]_/.

=head3 make_core_trampoline

  make_core_trampoline('CORE::open', 'main', prototype('CORE::open'))

Creates a trampoline for calling a core sub.  Essentially, a tiny sub
that figures out how we should be calling our core sub, puts in the
arguments in the right way, and bounces our control over to it.

If we could reliably use `goto &` on core builtins, we wouldn't need
this subroutine.

=head3 install_subs

  install_subs('My::Module', { 'read' => sub { die("Hallo\n"), ... }})

Given a package name and a hashref mapping names to a subroutine
reference (or C<undef>), this subroutine will install said subroutines
on their given name in that module.  If a name mapes to C<undef>, any
subroutine with that name in the target module will be remove
(possibly "unshadowing" a CORE sub of same name).

=head1 AUTHOR

Copyright 2013-2014, Niels Thykier E<lt>niels@thykier.netE<gt>

=head1 LICENSE

This module is free software.  You may distribute it under the
same terms as Perl itself.
