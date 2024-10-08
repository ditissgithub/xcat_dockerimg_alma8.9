#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#

#-----------------------------------------------------------------------------

=head1   mysqlsetup



 This script  automates the setup of the MySQL/MariaDB server  and creates the xCAT database to run
  xCAT on MySQL/MariaDB.
   Note: it will setup an xcat database (xcatdb),a xcatadmin id , and a MySQL root password.
   It will interact for the
   password to assign, unless the XCATMYSQLADMIN_PW and the XCATMYSQLROOT_PW
   env variables are set to the admin and mysql root password, resp.
   Setups up AIX and Linux,  but most work needs to be done on AIX.
   See man mysqlsetup for more information and the xCAT2.SetupMySQL.pdf
   documentation.

=cut

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
    $::XCATDIR  = $ENV{'XCATDIR'}  ? $ENV{'XCATDIR'}  : '/etc/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
    unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";
use DBI;
use xCAT::Utils;
use xCAT::NetworkUtils;
use Getopt::Long;
use xCAT::MsgUtils;
use xCAT::Table;
use Expect;
use Socket;
use strict;

#-----------------------------------------------------------------------------
# Main

$::progname = "mysqlsetup";
my $args = join ' ', @ARGV;
$::command = "$0 $args";
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;
$::installdir             = "/usr/local/mysql";  # current release of xcat-mysql
$::debianflag             = 0;

#$::installdir="/opt/xcat/mysql";  # next release of xcat-mysql

# parse the options
if (
    !GetOptions(
        'i|init'       => \$::INIT,
        'u|update'     => \$::UPDATE,
        'f|hostfile=s' => \$::HOSTFILE,
        'o|odbc'       => \$::SETUPODBC,
        'L|LL'         => \$::SETUPLL,
        'h|help'       => \$::HELP,
        'v|version'    => \$::VERSION,
        'V|verbose'    => \$::VERBOSE,
    )
  )
{
    &usage;
    exit(1);
}

# display the usage if -h or --help is specified
if ($::HELP)
{
    &usage;
    exit(0);
}

# display the version statement if -v or --version is specified
if ($::VERSION)
{
    my $version = xCAT::Utils->Version();
    xCAT::MsgUtils->message("I", $version);
    exit 0;
}
if ((!($::INIT)) && (!($::UPDATE)) && (!($::SETUPODBC)) && (!($::SETUPLL)))
{
    xCAT::MsgUtils->message("I", "Either -i or -u or -o flag must be chosen");
    &usage;
    exit(1);
}

# check to see if only odbc update,  no passwords needed
my $odbconly = 0;
if ((!($::INIT)) && (!($::UPDATE)) && (!($::SETUPLL)) && ($::SETUPODBC))
{
    $odbconly = 1;

}
if ((!($::HOSTFILE)) && ($::UPDATE) && ($::SETUPODBC))
{
    $odbconly = 1;

}
if (($::INIT) && ($::UPDATE))
{
    my $warning =
" The -i and -u flags may not be input to the command. Use one or the other. \n ";
    xCAT::MsgUtils->message("E", $warning);
    exit 1;
}
if (($::UPDATE) && ((!($::HOSTFILE)) && (!($::SETUPODBC))))
{
    my $warning =
" The -u flag requires the -o flag or the  -f flag pointing to a file that contains the list of hosts that you would like to add to database access.";
    xCAT::MsgUtils->message("E", $warning);
    exit 1;
}
if (($::HOSTFILE) && (!(-e ($::HOSTFILE))))
{
    my $warning = " The -f flag is pointing to a non-existing file.";
    xCAT::MsgUtils->message("E", $warning);
    exit 1;

}

#
# Get OS
#
if (xCAT::Utils->isAIX())
{
    $::osname = 'AIX';
}
else
{
    $::osname = 'Linux';
}

if (-e "/etc/debian_version") {
    $::debianflag = 1;
}

# determine whether redhat or sles
$::linuxos = xCAT::Utils->osver();

# is this MariaDB or MySQL
$::MariaDB = 0;
my $cmd;
if ($::debianflag) {
    $cmd = "dpkg -l | grep mariadb";
} else {
    $cmd = "rpm -qa | grep -i mariadb";    # check this is MariaDB not MySQL
}
xCAT::Utils->runcmd($cmd, -1);
if ($::RUNCMD_RC == 0) {
    $::MariaDB = 1;
}

#
# check to see if mysql is installed
#
$cmd = "rpm -qa | grep -i perl-DBD-mysql";
my $msg = "\nperl-DBD-mysql ";
if ($::debianflag) {
    if ($::MariaDB) {
        $cmd = "dpkg -l | grep -i mariadb-server";
        $msg = "\nmariadb-server ";
    } else {
        $cmd = "dpkg -l | grep mysql-server";
        $msg = "\nmysql-server ";
    }
}
xCAT::Utils->runcmd($cmd, 0);
if ($::RUNCMD_RC != 0)
{
    my $message =
"\n$msg is not installed.  If on AIX, it should be first obtained from the xcat dependency tarballs and installed before running this command.\n If on Linux, install from the OS CDs.";
    xCAT::MsgUtils->message("E", " $cmd failed. $message");
    exit(1);
}

# check to see if MySQL or MariaDB is running
$::mysqlrunning     = 0;
$::xcatrunningmysql = 0;

# Check if MySQL (mysqld) is running
my $cmd = "pidof mysqld";
xCAT::Utils->runcmd($cmd, 0);
if ($::RUNCMD_RC == 0) {
    $::mysqlrunning = 1;
    my $message = "MySQL is already running.";
    xCAT::MsgUtils->message("I", "$message");

    # Stop MySQL using pkill
    my $ret = system("pkill -f mysqld");
    if ($ret != 0) {
        xCAT::MsgUtils->message("E", "Failed to stop MySQL.");
        exit(1);
    } else {
        $::mysqlrunning = 0; # Service was stopped
    }
}

# Check if MariaDB (mariadbd) is running
$cmd = "pidof mariadbd";
xCAT::Utils->runcmd($cmd, 0);
if ($::RUNCMD_RC == 0) {
    $::mysqlrunning = 1;
    my $message = "MariaDB is already running.";
    xCAT::MsgUtils->message("I", "$message");

    # Stop MariaDB using pkill
    my $ret = system("pkill -f mariadbd");
    if ($ret != 0) {
        xCAT::MsgUtils->message("E", "Failed to stop MariaDB.");
        exit(1);
    } else {
        $::mysqlrunning = 0; # Service was stopped
    }
}



if (-e ("/etc/xcat/cfgloc"))    # check to see if xcat is using mysql
{                               # cfgloc exists
    $cmd = "fgrep mysql /etc/xcat/cfgloc";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC == 0)
    {
        if ($::INIT)
        {
            my $message =
"The /etc/xcat/cfgloc file is already configured for MySQL and xCAT is using mysql or mariadb as it's database. No xCAT setup is required.";
            xCAT::MsgUtils->message("I", "$message");
        }
        $::xcatrunningmysql = 1;
    }
}

#
# if AIX, Set memory unlimited.  Linux defaults unlimited
#
if ($::osname eq 'AIX')
{
    &setulimits;
}

#  if not just odbc update  and not already running mysql or mysqlsetup -u  or -L
#  Get root and admin passwords
#
if ((($odbconly == 0) && ($::xcatrunningmysql == 0)) || $::UPDATE || $::SETUPLL)
{    # not just updating the odbc
    if ($ENV{'XCATMYSQLADMIN_PW'})    # input env sets the password
    {
        my $pw = $ENV{'XCATMYSQLADMIN_PW'};
        if ($pw =~ m/[^a-zA-Z0-9]/) {    # if not alpha-numerid
            my $warning =
" The password in the env variable XCATMYSQLADMIN_PW is not alpha-numeric.";
            xCAT::MsgUtils->message("E", $warning);
            exit 1;
        }

        $::adminpassword = $ENV{'XCATMYSQLADMIN_PW'};

    }
    else                                 # prompt for password
    {
        my $msg = "Input the alpha-numberic  password for xcatadmin in the MySQL database: ";
        xCAT::MsgUtils->message('I', "$msg");
        `stty -echo`;
        chop($::adminpassword = <STDIN>);
        `stty echo`;

        if ($::adminpassword =~ m/[^a-zA-Z0-9]/) {    # if not alpha-numerid
            my $warning =
"The input password  is not alpha-numeric. Rerun the command an input an alpha-numeric password.";
            xCAT::MsgUtils->message("E", $warning);
            exit 1;
        }
    }
    if ($ENV{'XCATMYSQLROOT_PW'})    # input env sets the password
    {
        my $pw = $ENV{'XCATMYSQLROOT_PW'};
        if ($pw =~ m/[^a-zA-Z0-9]/) {    # if not alpha-numerid
            my $warning =
" The password in the env variable XCATMYSQLROOT_PW is not alpha-numeric.";
            xCAT::MsgUtils->message("E", $warning);
            exit 1;
        }

        $::rootpassword = $ENV{'XCATMYSQLROOT_PW'};

    }
    else                                 # prompt for password
    {

        my $msg = "Input the password for root in the MySQL database: ";
        xCAT::MsgUtils->message('I', "$msg");
        `stty -echo`;
        chop($::rootpassword = <STDIN>);
        `stty echo`;

        if ($::rootpassword =~ m/[^a-zA-Z0-9]/) {    # if not alpha-numerid
            my $warning =
"The input password  is not alpha-numeric. Rerun the command an input an alpha-numeric password.";
            xCAT::MsgUtils->message("E", $warning);
            exit 1;
        }

    }
}

# initial setup request, if not already running mysql
my $hostfile_configured=0;
if (($::INIT) && ($::xcatrunningmysql == 0))
{
    # MySQL not running, then initialize the database
    if ($::mysqlrunning == 0)
    {
        # Add mysql user and group for AIX
        # Correct directory permissions
        #
        &fixinstalldir;

        #
        # Init mysql db and setup my.cnf
        #
        &initmysqldb;

        #
        # Start MySQL server
        #
        &mysqlstart;

        #
        # Setup MySQL to restart on reboot
        #
        &mysqlreboot;

        #
        # set mysql root password in database
        #
        #
        &setupmysqlroot;
    }

    # Verify the mysql root password, if it is wrong, do nothing and die.
    &verifymysqlroot;

    #
    # Backup current database
    #
    my $homedir = xCAT::Utils->getHomeDir();
    $::backupdir = $homedir;
    if ($::osname eq 'AIX')
    {
        $::backupdir .= "xcat-dbback";
    }
    else
    {
        $::backupdir .= "/xcat-dbback";
    }

    &backupxcatdb;

    # shutdown the xcatd daemon while migrating
    &shutdownxcatd;


    #
    #  Get MN name from site.master in backed up database
    # if that does not exist use resolved hostname
    # double check site.master for resolution
    my $sitefile = "$::backupdir/site.csv";
    my $cmd      = "grep master $sitefile";
    my @output   = xCAT::Utils->runcmd($cmd, -1);
    my $hname;
    # from site.master
    if ($::RUNCMD_RC == 0 )
    {
        (my $attr, my $master) = split(",", $output[0]);
        (my $q, $hname) = split("\"", $master);
        chomp $hname;

    }

    if( "$hname" eq ""){
        $hname = `hostname`;
        chomp $hname;
    }

    #my ($name, $aliases, $addrtype, $length, @addrs) = gethostbyname($hname);
    my $ipaddr = xCAT::NetworkUtils->getipaddr($hname);
    if ($ipaddr)
    {
        $::MN = $ipaddr;
    }
    else
    {
        xCAT::MsgUtils->message("E", "Hostname resolution for $hname failed.");
        exit(1);
    }

    # if xcat not already configured to run mysql, then add xcat info to the DB
    if ($::xcatrunningmysql == 0)
    {

        #
        # Create xcatd  database
        # Create xcatadmin in the database
        # Add Management Node to database access
        #
        &setupxcatdb;

        #
        # create cfgloc file
        #
        &createcfgloc;

        if ($::HOSTFILE)
        {
           &addhosts;
           $hostfile_configured=1
        }

        #
        # Restore backed up database into MySQL
        #
        &restorexcatdb;

        if ($::osname eq 'AIX')
        {
            xCAT::MsgUtils->message("I", "xCAT is now running on the MySQL database.\nYou should log out and back in, so that the new ulimit settings will take affect.");
        } else {
            xCAT::MsgUtils->message("I", "xCAT is now running on the MySQL database.");
        }
    }

}    # end initialization
else {
    # MySQL not running, restart it
    if ($::mysqlrunning == 0) {
        &mysqlstart;
    }
}

if ($::SETUPODBC)
{

    #
    #  set up the ODBC on the Management Node
    #

    &setupODBC;

}
if ($::SETUPLL)
{

    #
    # Add special Loadleveler setup
    #

    &setupLL;

}


# if input a list of hosts to add to the database, to give access to MySQL
if (($::HOSTFILE) && ($hostfile_configured == 0))
{
    &addhosts;

}
exit;

#####################################
#  subroutines
#####################################

#-----------------------------------------------------------------------------

=head3    usage

        Displays message for -h option

=cut

#-----------------------------------------------------------------------------

sub usage
{
    xCAT::MsgUtils->message(
        'I',
"Usage:\nmysqlsetup - Performs the setup of MySQL or MariaDB for xCAT to use as its database. See man mysqlsetup for more information."
    );
    my $msg =
"mysqlsetup <-h|--help>\n           <-v|--version>\n           <-i|--init> [-f|hostfile] [-o|--odbc] [-L|--LL] [-V|--verbose]\n           <-u|--update> <-f|hostfile> [-o|--odbc] [-L|--LL] [-V|--verbose]\n           <-o|--odbc> [-V|--verbose]\n           <-L|--LL> [-V|--verbose]";

    xCAT::MsgUtils->message('I', "$msg");
}

#-----------------------------------------------------------------------------

=head3    setulimits

     sets ulimits unlimited, needed to run MySQL
         update /etc/security/limits with the info

=cut

#-----------------------------------------------------------------------------

sub setulimits
{
    my $limitsfile    = "/etc/security/limits";
    my $limitstmpfile = "/etc/security/limits.tmp";
    my $limitsbackup  = "/etc/security/limits.backup";

    # backup ulimits if not already backed up
    if (!(-e ("$limitsbackup")))
    {
        $cmd = "cp $limitsfile $limitsbackup";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }
    }

    # add ulimits for root to /etc/security/limits
    unless (open(LIMITS, "<$limitsfile"))
    {
        xCAT::MsgUtils->message('E', "Error opening $limitsfile.");
        exit(1);
    }
    unless (open(LIMITSTMP, ">$limitstmpfile"))
    {
        xCAT::MsgUtils->message('E', "Error opening $limitstmpfile.");
        exit(1);
    }
    my $rootstanza = 0;
    foreach my $line (<LIMITS>)
    {
        if ($rootstanza == 1)
        {    # dealing with root stanza, skip all entries
            if (!($line =~ /:/))
            {    # still in root stanza
                next;    # skip root stanza info
            }
            else
            {            # continue through the file
                $rootstanza = 0;
            }
        }
        print LIMITSTMP $line;
        if ($line =~ /root:/)
        {                # at root stanza, add unlimits
            print LIMITSTMP "        fsize = -1\n";
            print LIMITSTMP "        core= -1\n";
            print LIMITSTMP "        cpu= -1\n";
            print LIMITSTMP "        data= -1\n";
            print LIMITSTMP "        rss= -1\n";
            print LIMITSTMP "        stack= -1\n";
            print LIMITSTMP "        nofiles= 102400\n";
            print LIMITSTMP "\n";
            $rootstanza = 1;
        }
    }

    close(LIMITS);
    close(LIMITSTMP);

    # copy new limits to old
    $cmd = "cp $limitstmpfile $limitsfile";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("E", " $cmd failed.");
        exit(1);
    }

}

#-----------------------------------------------------------------------------

=head3    backupxcatdb

   Backup xCATdb

=cut

#-----------------------------------------------------------------------------

sub backupxcatdb

{

    # If there is no backup or the /etc/xcat/cfgloc file does not point to
    # mysql, then we backup the database
    my $sitefile = "$::backupdir/site.csv";

    if ((!(-e $sitefile)) || ($::xcatrunningmysql == 0))
    {
        xCAT::MsgUtils->message(
            "I",
"Backing up xCAT Database to $::backupdir.\nThis could take several minutes."
        );
        if (!(-e $::backupdir))
        {    # does not exist, make it
            my $cmd = "mkdir -p $::backupdir";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
        }
        else
        {    # remove contents

            my $cmd = "rm -f $::backupdir/*";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
        }

        # back it up
        my $cmd = "dumpxCATdb -p $::backupdir";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }
    }

}

#-----------------------------------------------------------------------------

=head3    shutdownxcatd

  shutdown the daemon

=cut

#-----------------------------------------------------------------------------

sub shutdownxcatd

{
    my $msg = "Shutting down the xcatd daemon during database migration.";
    xCAT::MsgUtils->message('I', "$msg");
    my $xcmd;
    if ($::osname eq 'AIX')
    {
        $xcmd = "stopsrc -s xcatd";
        system($xcmd);

    }
    else
    {
        #$xcmd = "service xcatd stop";
#        my $ret = xCAT::Utils->stopservice("xcatd");
        my $ret = "pkill xcatd";
        return $ret;
    }

}

#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------

=head3   fixinstall

        If AIX, Fixes ownership and permssion on install
         adds mysql user and group

=cut

#-----------------------------------------------------------------------------

sub fixinstalldir
{

    if ($::osname eq 'AIX')
    {

        #
        # mk mysql group and user
        #
        my $cmd = "lsgroup mysql";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {

            # mysql group does not exist, need to make it
            $cmd = "mkgroup mysql";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
        }
        $cmd = "lsuser mysql";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {

            # mysql user does not exist, need to make it
            $cmd = "mkuser pgrp=mysql mysql";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
        }

        #
        # correct installed directory permissions
        #
        xCAT::MsgUtils->message(
            'I',
"Fixing install directory permissions.\nThis may take a few minutes."
        );
        my $mysqldir = $::installdir;
        $mysqldir .= "\/*";
        $cmd = "chown -R mysql $mysqldir";
        xCAT::Utils->runcmd($cmd, 0);

        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }
        $cmd = "chgrp -R mysql $mysqldir";
        xCAT::Utils->runcmd($cmd, 0);

        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }

    }
}

#-----------------------------------------------------------------------------

=head3   initmysqldb


    Create the MySQL data directory and initialize the grant tables
        Setup my.cnf

=cut

#-----------------------------------------------------------------------------
sub initmysqldb
{
    my $cmd;

    if (($::osname eq 'AIX') && (!(-e "/etc/my.cnf")))
    {
        $cmd = "cp $::installdir/support-files/my-large.cnf  /etc/my.cnf";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {

            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }

    }


    # for AIX, insert  datadir=/var/lib/mysql in the [mysqld] stanza
    # of the /etc/my.cnf file,if it is not already there
    if ($::osname eq 'AIX')
    {
        $cmd = "fgrep datadir /etc/my.cnf";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {

            $cmd =
"awk '{gsub(\"\\\\[mysqld]\",\"\\[mysqld]\\ndatadir=/var/lib/mysql \"); print}'   /etc/my.cnf > /etc/my.cnf.xcat";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {

                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
            $cmd = "cp -p  /etc/my.cnf.xcat  /etc/my.cnf";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {

                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
        }

        #
        # make data dir owned by mysql and root everything else
        #
        my $mysqldir = $::installdir;
        $mysqldir .= "\/*";
        $cmd = "chown -R root $mysqldir";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }
        my $mysqldatadir = "$::installdir/data";
        $mysqldatadir .= "\/*";
        $cmd = "chown -R mysql $mysqldatadir";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }
        $cmd = "chgrp -R mysql $mysqldatadir";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
            exit(1);
        }

        # make the database directory if it does not exist and
        # make mysql the owner
        if (!(-e ("/var/lib/mysql")))
        {
            $cmd = "mkdir -p /var/lib/mysql";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
            $cmd = "chown -R mysql /var/lib/mysql";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }
            $cmd = "chgrp -R mysql /var/lib/mysql";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("E", " $cmd failed.");
                exit(1);
            }

        }
    }    # end AIX only

    #bind-adress line in my.cnf should comment out
    #on Ubuntu16.04, the bind-address line is in the mariadb.conf.d/50-server.cnf
    #on SLE15, the bind-address line is in the /etc/my.cnf
    my $bind_file;
    if (-e "/etc/mysql/mariadb.conf.d/50-server.cnf")
    {
        $bind_file = "/etc/mysql/mariadb.conf.d/50-server.cnf";
    } elsif (-e "/etc/mysql/my.cnf")
    {
        $bind_file = "/etc/mysql/my.cnf";
    } else {
        $bind_file = "/etc/my.cnf";
    }
    $cmd = "sed 's/^bind/#&/' $bind_file > /tmp/my.cnf; mv -f /tmp/my.cnf $bind_file;chmod 644 $bind_file";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("E", " comment the bind-address line in $bind_file failed: $cmd.");
        exit(1);
    }

    # Create the MySQL data directory and initialize the grant tables
    # if not already setup
    my $cmd2 =
"ulimit -n unlimited; ulimit -m unlimited; ulimit -d unlimited;ulimit -f unlimited; ulimit -s unlimited;";
    if ($::osname eq 'AIX')
    {
        $cmd = $cmd2;
        $cmd .=
"$::installdir/scripts/mysql_install_db --user=mysql --basedir=$::installdir";
    }
    else
    {
        my $sqlcmd = "/usr/bin/mysql_install_db";
        if (!(-x ($sqlcmd))) {
            xCAT::MsgUtils->message("E", "$sqlcmd is not available, please install required mysql/mariadb packages");
            exit(1);
        }

        $cmd = "$sqlcmd --user=mysql";
        # On rhels7.7, /usr/bin/mysql_install_db requires /usr/libexec/resolveip
        # Link it to /usr/bin/resolveip for all OSes, just in case some future releases have the same requirement
        my $resolveip="/usr/libexec/resolveip";
        if (!(-x ($resolveip))) {
            my $linkcmd="ln -s /usr/bin/resolveip $resolveip";
            xCAT::Utils->runcmd($linkcmd, 0);
        }
    }
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {

        xCAT::MsgUtils->message("E", " $cmd failed.");

        exit(1);
    }

}

#-----------------------------------------------------------------------------

=head3   mysqlstart


    Start the mysql server

=cut

#-----------------------------------------------------------------------------
sub mysqlstart {
    my $cmd;
    my $ret = 0;

    if ($::osname eq 'AIX') {
        my $hostname = `hostname`;
        chomp $hostname;

        my $cmd2 = "ulimit -n unlimited; ulimit -m unlimited; ulimit -d unlimited;ulimit -f unlimited; ulimit -s unlimited;";
        $cmd = $cmd2;
        $cmd .= "/usr/bin/mysqld --user=mysql --basedir=$::installdir --datadir=/var/lib/mysql --log-error=/var/lib/mysql/$hostname.err --pid-file=/var/lib/mysql/$hostname.pid --socket=/tmp/mysql.sock --port=3307 &";
        $ret = xCAT::Utils->runcmd($cmd, 0);
    } else {
        if ($::MariaDB == 1) {    # running MariaDB
            if ($::linuxos =~ /rh.*|ol.*|rocky.*|alma.*|sles15.*/) {
                $cmd = "/usr/bin/mariadbd --user=mysql --basedir=/usr --datadir=/var/lib/mysql --socket=/var/lib/mysql/mysql.sock --port=3307 &";
            } else {              # SLES
                $cmd = "/usr/bin/mysqld --user=mysql --basedir=/usr --datadir=/var/lib/mysql --socket=/var/lib/mysql/mysql.sock --port=3307 &";
            }
        } else {    # it is mysql
            if ($::linuxos =~ /rh.*|ol.*|rocky.*|alma.*/) {
                $cmd = "nohup /usr/bin/mysqld_safe --user=mysql --basedir=/usr --datadir=/var/lib/mysql --socket=/var/lib/mysql/mysql.sock --port=3307 > /dev/null 2>&1 &";
            } else {              # SLES
                $cmd = "/usr/bin/mysqld --user=mysql --basedir=/usr --datadir=/var/lib/mysql --socket=/var/lib/mysql/mysql.sock --port=3307 &";
            }
        }
        $ret = xCAT::Utils->runcmd($cmd, 0);
    }

    if ($ret != 0) {
        xCAT::MsgUtils->message("E", " failed to start mysql/mariadb.");
        exit(1);
    }

    # Ensure service has started
    sleep 10;    # Adjust as necessary

    # Check for process running
    #my $mysql_process_name = "mysqld_safe";
    #my $cmd_check = "ps -ef | grep -E '$mysql_process_name' | grep -v grep";
    #my @output = xCAT::Utils->runcmd($cmd_check, 0);

    #if (grep(/$mysql_process_name/, @output)) {
        #return;    # MySQL/MariaDB started successfully
    #} else {
        #xCAT::MsgUtils->message("E", "Could not start the mysql/mariadb daemon.");
        #$cmd = "nohup /usr/bin/mysqld_safe --user=mysql --basedir=/usr --datadir=/var/lib/mysql --soc        ket=/var/lib/mysql/mysql.sock --port=3307 > /dev/null 2>&1 &";
        #exit(1);
    #}
#}

# Check for process running
    my $mysql_process_name = "mysqld_safe";
    my $cmd_check = "ps -ef | grep -E '$mysql_process_name' | grep -v grep";
    my @output = `$cmd_check`;

    if (grep(/$mysql_process_name/, @output)) {
        print "MySQL/MariaDB is already running.\n";
    } else {
        print "MySQL/MariaDB is not running. Starting it now...\n";
        my $cmd_start = "nohup /usr/bin/mysqld_safe --user=mysql --basedir=/usr --datadir=/var/lib/mysql --socket=/var/lib/mysql/mysql.sock --port=3307 > /dev/null 2>&1 &";
        system($cmd_start);
        sleep(5);  # Allow time for MySQL/MariaDB to start

        # Check again if MySQL/MariaDB started successfully
        @output = `$cmd_check`;
        if (grep(/$mysql_process_name/, @output)) {
           print "MySQL/MariaDB started successfully.\n";
        } else {
           print "Failed to start MySQL/MariaDB.\n";
           exit(1);
        }
     }
}


#-----------------------------------------------------------------------------

=head3   mysqlreboot


    Setup for MySQL to start on reboot

=cut

#-----------------------------------------------------------------------------
sub mysqlreboot {
    my $cmd;
    if ($::osname eq 'AIX') {
        # Check if MySQL entry exists in inittab
        $cmd = "fgrep mysql /etc/inittab";
        xCAT::Utils->runcmd($cmd, -1);

        # If MySQL entry does not exist in inittab
        if ($::RUNCMD_RC != 0) {
            # Backup inittab
            if (!(-e "/etc/inittab.org")) {
                $cmd = "cp -p /etc/inittab /etc/inittab.org";
                xCAT::Utils->runcmd($cmd, 0);
                if ($::RUNCMD_RC != 0) {
                    xCAT::MsgUtils->message("E", "$cmd failed. Could not backup inittab.");
                    exit(1);
                }
            }

            # Modify inittab to include MySQL startup entry
            $cmd = "awk '{gsub(\"xcatd:2:once:/opt/xcat/sbin/restartxcatd > /dev/console 2>&1\",\"mysql:2:once:/usr/bin/mysqld_safe --user=mysql \\& \\nxcatd:2:once:/opt/xcat/sbin/restartxcatd > /dev/console 2>\\&1\"); print}' /etc/inittab > /etc/inittab.xcat";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0) {
                xCAT::MsgUtils->message("E", "$cmd failed.");
                exit(1);
            }

            # Apply the modified inittab
            $cmd = "cp -p /etc/inittab.xcat /etc/inittab";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0) {
                xCAT::MsgUtils->message("E", "$cmd failed. MySQL will not restart on reboot.");
            }
        }
    }
    else {    # Linux
        if ($::MariaDB == 1) {    # MariaDB not MySQL
            if ($::linuxos =~ /rh.*|ol.*|rocky.*|alma.*|sles15.*/) {
                $cmd = "chkconfig mariadb on";
            } else {              # SLES
                $cmd = "chkconfig mysql on";
                if ($::debianflag) {
                    $cmd = "update-rc.d mysql defaults";
                }
            }
        } else {    # MySQL
            if ($::linuxos =~ /rh.*|ol.*|rocky.*|alma.*/) {
                $cmd = "chkconfig mysqld on";
            } else {              # SLES
                $cmd = "chkconfig mysql on";
                if ($::debianflag) {
                    $cmd = "update-rc.d mysql defaults";
                }
            }
        }
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0) {
            xCAT::MsgUtils->message("E", "$cmd failed. MySQL will not restart on reboot.");
        }
    }
}


sub verifymysqlroot
{
    # Verify if mysql has an correct user input root password
    if ($::osname eq 'AIX')
    {
        my $cmd2 =
"ulimit -n unlimited; ulimit -m unlimited; ulimit -d unlimited;ulimit -f unlimited; ulimit -s unlimited;";
        $cmd = $cmd2;
        $cmd .= "$::installdir/bin/mysqladmin -u root -p$::rootpassword version";
    }
    else
    {
        $cmd = "/usr/bin/mysqladmin -u root -p$::rootpassword version";
    }

    my $tmpv = $::VERBOSE;
    $::VERBOSE = 0;
    xCAT::Utils->runcmd($cmd, 0);
    $::VERBOSE = $tmpv;
    if ($::RUNCMD_RC == 0)
    {
        # User has input an correct root passwd. That is fine. Do nothing and go head.
        return
    }

    # The password is wrong, warn the user and die.
    xCAT::MsgUtils->message(
        "E",
        "Wrong MySQL root password."
    );
    exit 1;
}

#-----------------------------------------------------------------------------

=head3   setupmysqlroot


    Set mysql root password in the database

=cut

#-----------------------------------------------------------------------------

sub setupmysqlroot

{
    my $cmd;

    # set root password in database
    if ($::osname eq 'AIX')
    {
        my $cmd2 =
"ulimit -n unlimited; ulimit -m unlimited; ulimit -d unlimited;ulimit -f unlimited; ulimit -s unlimited;";
        $cmd = $cmd2;
        $cmd .= "$::installdir/bin/mysqladmin -u root password $::rootpassword";
    }
    else
    {
        $cmd = "/usr/bin/mysqladmin -u root password $::rootpassword";
    }

    # secure passwd in verbose mode
    my $tmpv = $::VERBOSE;
    $::VERBOSE = 0;
    xCAT::Utils->runcmd($cmd, 0);
    $::VERBOSE = $tmpv;
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message(
            "I",
"Warning, mysqladmin -u root password command failed, trying to set root password in MySQL. If root id has been defined in MySQL, and has a password then this message can be ignored."
        );

    }

}

#-----------------------------------------------------------------------------

=head3    setupxcatdb

      Creates the xcatdb in MySQL
      Add xcatadmin to the database
          Give Management Node database access

=cut

#-----------------------------------------------------------------------------

sub setupxcatdb

{
    my $mysql;
    my $timeout  = 10;    # sets Expect default timeout, 0 accepts immediately
    my $pwd_sent = 0;
    my $pwd_prompt = 'Enter password: ';
    my $mysql_prompt;
    if ($::MariaDB == 1) {    # setup MariaDB
        $mysql_prompt = 'MariaDB \[\(none\)\]> ';
    } else {
        $mysql_prompt = 'mysql> ';
    }
    my $expect_log = undef;
    my $debug      = 0;

    #if ($::VERBOSE)
    #{
    #    $debug = 1;
    #}
    $mysql = new Expect;
    my $createuser =
      "CREATE USER xcatadmin IDENTIFIED BY \'$::adminpassword\';\r";
    my $grantall = "";
    $grantall = "GRANT ALL on xcatdb.* TO xcatadmin@";
    $grantall .= "\'";
    $grantall .= "$::MN";
    $grantall .= "\'";
    $grantall .= " IDENTIFIED BY \'$::adminpassword\';\r";

    #GRAND user xcatadmin to localhost account
    my $grantall_localhost = "";
    $grantall_localhost = "GRANT ALL on xcatdb.* TO xcatadmin@";
    $grantall_localhost .= "\'";
    $grantall_localhost .= "localhost";
    $grantall_localhost .= "\'";
    $grantall_localhost .= " IDENTIFIED BY \'$::adminpassword\';\r";

    #GRAND root to host account
    my $grantroot = "";
    $grantroot = "GRANT ALL on xcatdb.* TO root@";
    $grantroot .= "\'";
    $grantroot .= "$::MN";
    $grantroot .= "\'";
    $grantroot .= " IDENTIFIED BY \'$::rootpassword\';\r";

    #
    # -re $pwd_prompt
    #     Enter the password for root
    #
    # -re $mysql_prompt
    #   mysql> Enter the Create Database SQL command and exit
    #
    #

    # disable command echoing
    #$mysql->slave->stty(qw(sane -echo));

    #
    # exp_internal(1) sets exp_internal debugging
    # to STDERR.
    #
    #$mysql->exp_internal(1);
    $mysql->exp_internal($debug);

    #
    # log_stdout(0) prevent the program's output from being shown.
    #  turn on if debugging error
    #$mysql->log_stdout(1);
    $mysql->log_stdout($debug);

    my $spawncmd;
    if ($::osname eq 'AIX')
    {
        $spawncmd = "$::installdir/bin/mysql  -u root -p";
    }
    else
    {
        $spawncmd = "/usr/bin/mysql -u root -p";
    }
    unless ($mysql->spawn($spawncmd))
    {
        xCAT::MsgUtils->message("E",
            "Unable to run $spawncmd to create database and add MN.");
        return;

    }

    #
    # setup SQL commands
    #

    my @result = $mysql->expect(
        $timeout,
        [
            $pwd_prompt,
            sub {
                $mysql->send("$::rootpassword\r");
                $mysql->clear_accum();
                $mysql->exp_continue();
            }
        ],
        [
            $mysql_prompt,
            sub {

                $mysql->send("CREATE DATABASE xcatdb;ALTER DATABASE xcatdb DEFAULT CHARACTER SET latin1;\r");
                $mysql->clear_accum();
                $mysql->send("$createuser");
                $mysql->clear_accum();
                $mysql->send("$grantall");
                $mysql->clear_accum();
                $mysql->send("$grantall_localhost");
                $mysql->clear_accum();
                $mysql->send("$grantroot");
                $mysql->clear_accum();
                $mysql->send("exit;\r");

            }
        ]
    );
    ##########################################
    # Expect error - report and quit
    ##########################################
    if (defined($result[1]))
    {
        my $errmsg = $result[1];
        $mysql->soft_close();
        xCAT::MsgUtils->message("E",
            "Failed creating database. $errmsg");
        exit(1);

    }
    $mysql->soft_close();

}

#-----------------------------------------------------------------------------

=head3    setupLL

      Adds special LoadLeveler setup in MySQL

=cut

#-----------------------------------------------------------------------------

sub setupLL

{
    my $mysql;
    my $timeout  = 10;    # sets Expect default timeout, 0 accepts immediately
    my $pwd_sent = 0;
    my $pwd_prompt = 'Enter password: ';
    my $mysql_prompt;
    if ($::MariaDB == 1) {    # setup MariaDB
        $mysql_prompt = 'MariaDB \[\(none\)\]> ';
    } else {
        $mysql_prompt = 'mysql> ';
    }
    my $expect_log = undef;
    my $debug      = 0;

    #if ($::VERBOSE)
    #{
    #    $debug = 1;
    #}
    $mysql = new Expect;
    my $setLLfunction =
      "SET GLOBAL log_bin_trust_function_creators=1;\r";

    #
    # -re $pwd_prompt
    #     Enter the password for root
    #
    # -re $mysql_prompt
    #   mysql> Enter the log_bin_trust_function_creators command and exit
    #
    #

    # disable command echoing
    #$mysql->slave->stty(qw(sane -echo));

    #
    # exp_internal(1) sets exp_internal debugging
    # to STDERR.
    #
    #$mysql->exp_internal(1);
    $mysql->exp_internal($debug);

    #
    # log_stdout(0) prevent the program's output from being shown.
    # log_stdout shows output, turn on if debugging error
    #$mysql->log_stdout(1);
    $mysql->log_stdout($debug);

    my $spawncmd;
    if ($::osname eq 'AIX')
    {
        $spawncmd = "$::installdir/bin/mysql  -u root -p";
    }
    else
    {
        $spawncmd = "/usr/bin/mysql -u root -p";
    }
    unless ($mysql->spawn($spawncmd))
    {
        xCAT::MsgUtils->message("E",
            "Unable to run $spawncmd to add LL setup.");
        return;

    }

    #
    # setup SQL commands
    #

    my @result = $mysql->expect(
        $timeout,
        [
            $pwd_prompt,
            sub {
                $mysql->send("$::rootpassword\r");
                $mysql->clear_accum();
                $mysql->exp_continue();
            }
        ],
        [
            $mysql_prompt,
            sub {

                $mysql->send("$setLLfunction");
                $mysql->clear_accum();
                $mysql->send("exit;\r");

            }
        ]
    );
    ##########################################
    # Expect error - report and quit
    ##########################################
    if (defined($result[1]))
    {
        my $errmsg = $result[1];
        $mysql->soft_close();
        xCAT::MsgUtils->message("E",
            "Failed LoadLeveler setup. $errmsg");
        exit(1);

    }
    $mysql->soft_close();
    xCAT::MsgUtils->message("I", "LoadLeveler setup complete.");

}

#-----------------------------------------------------------------------------

=head3   addhosts

         Will add all host ids that need access to the MySQL database.
                 User will input names, ipaddress or wild cards like 9.112.%.%
                 or %.ibm.com in a file after the -f flag.

=cut

#-----------------------------------------------------------------------------

sub addhosts

{
    my @hosts;
    my $debug = 0;

    #if ($::VERBOSE)
    #{
    #    $debug = 1;
    #}

    open(HOSTFILE, "<$::HOSTFILE")
      or
      xCAT::MsgUtils->message('S', "Cannot open $::HOSTFILE for node list. \n");
    foreach my $line (<HOSTFILE>)
    {
        chop $line;
        push @hosts, $line;    # add hosts
    }
    close HOSTFILE;
    my $mysql;
    my $timeout  = 10;    # sets Expect default timeout, 0 accepts immediately
    my $pwd_sent = 0;
    my $pwd_prompt = 'Enter password: ';
    my $mysql_prompt;
    if ($::MariaDB == 1) {    # setup MariaDB
        $mysql_prompt = 'MariaDB \[\(none\)\]> ';
    } else {
        $mysql_prompt = 'mysql> ';
    }
    my $expect_log = undef;

    foreach my $host (@hosts)
    {
        my $grantall = "";
        $grantall = "GRANT ALL on xcatdb.* TO xcatadmin@";
        $grantall .= "\'";
        $grantall .= "$host";
        $grantall .= "\'";
        $grantall .= " IDENTIFIED BY \'$::adminpassword\';\r";
        $mysql = new Expect;

        #
        # -re $pwd_prompt
        #     Enter the password for root
        #
        # -re $mysql_prompt
        #   mysql> Enter the GRANT ALL SQL command for each host and exit
        #
        #

        # disable command echoing
        #$mysql->slave->stty(qw(sane -echo));

        #
        # exp_internal(1) sets exp_internal debugging
        # to STDERR.
        #
        #$mysql->exp_internal(1);
        $mysql->exp_internal($debug);

        #
        # log_stdout(0) prevent the program's output from being shown.
        # turn on to debug error
        #$mysql->log_stdout(1);
        $mysql->log_stdout($debug);
        my $spawncmd;
        if ($::osname eq 'AIX')
        {
            $spawncmd = "$::installdir/bin/mysql  -u root -p";
        }
        else
        {
            $spawncmd = "/usr/bin/mysql -u root -p";
        }
        unless ($mysql->spawn($spawncmd))
        {
            xCAT::MsgUtils->message(
                "E",
                "Unable to run $spawncmd to grant host access to the  database."
            );
            return;

        }

        #
        # setup SQL commands
        #

        my @result = $mysql->expect(
            $timeout,
            [
                $pwd_prompt,
                sub {
                    $mysql->send("$::rootpassword\r");
                    $mysql->clear_accum();
                    $mysql->exp_continue();
                }
            ],
            [
                $mysql_prompt,
                sub {

                    $mysql->send("$grantall");
                    $mysql->clear_accum();
                    $mysql->send("exit;\r");

                }
            ]
        );
        ##########################################
        # Expect error - report and quit
        ##########################################
        if (defined($result[1]))
        {
            my $errmsg = $result[1];
            $mysql->soft_close();
            xCAT::MsgUtils->message("E",
                "Failed adding  hosts. $errmsg");
            exit(1);

        }
        $mysql->soft_close();
    }
}

#-----------------------------------------------------------------------------

=head3   setupODBC

         Will setup the ODBC. Only needed if C, C++ applications are running
                 that need access to the MySQL database for example LoadLeveler.

=cut

#-----------------------------------------------------------------------------

sub setupODBC

{

    #
    # check to see if correct rpms are installed
    #
    # for all OS need unixODBC rpm
    my $cmd = "rpm -qa | grep unixODBC";
    if ($::debianflag) {
        $cmd = "dpkg -l | grep unixodbc";
    }
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my $message =
"unixODBC is not installed.  If on AIX, it should be first obtained from the xcat dependency tarballs and installed before we can setup the ODBC. If on Linux, install from the OS CDs.";
        xCAT::MsgUtils->message("E", " $message");
        exit(1);
    }

    # for aix and redhat
    if (($::linuxos =~ /rh.*|ol.*|rocky.*|alma.*/) || ($::osname eq 'AIX'))
    {
        $cmd = "rpm -qa | grep mysql-connector-odbc";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $message =
"xcat-connector-odbc is not installed.  It should be first obtained from the xcat dependency tarballs and installed before running this command. If on Linux, install from the OS CDs.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
    }
    elsif ($::debianflag) {
        $cmd = "dpkg -l | grep libmyodbc";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $message = "\nlibmyodbc is not installed.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
    }
    else    # sles
    {
        $cmd = "rpm -qa | grep mysql-client";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $message =
"mysql-client is not installed.  It should be first installed from the SLES CDs.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
        $cmd = "rpm -qa | grep libmysqlclient";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $message =
"libmysqlclient is not installed.  It should be first installed from the SLES CDs.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
        $cmd = "rpm -qa | grep MyODBC-unixODBC";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $message =
"MyODBC-unixODBC is not installed.  It should be first installed from the SLES CDs.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
    }    # end sles
    my @rpmoutput;
    my $odbcinstfile;
    my $odbcfile;
    my $message;

    # configure the ODBC, again SLES different than the rest
    my $xcatconfig       = "/etc/xcat/cfgloc";
    my $xcatconfigbackup = "/etc/xcat/cfgloc.mysql";
    if (!(-e ($xcatconfig)) && (!(-e ($xcatconfigbackup))))
    {
        $message =
"The $xcatconfig and $xcatconfigbackup files are missing. You need to configure xCAT for MySQL before setting up the ODBC.";
        xCAT::MsgUtils->message("E", "$message");
        exit(1);

    }
    $cmd = "fgrep -i  host $xcatconfig";
    my @output;
    @output = xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)    # then try backup
    {
        $cmd = "fgrep -i  host $xcatconfigbackup";
        @output = xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)    # then try backup
        {
            $message =
"Cannot find host info in the cfgloc or cfgloc.mysql file. Configuration of ODBC cannot continue.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
    }

    # get host and password from cfgloc
    (my $connstring, my $adminid, my $passwd) = split(/\|/, $output[0]);
    (my $database,   my $id,      my $server) = split(/=/,  $connstring);

    if (($::linuxos =~ /rh.*|ol.*|rocky.*|alma.*/) || ($::osname eq 'AIX'))
    {
        $odbcinstfile = "/etc/odbcinst.ini";
        $odbcfile     = "/etc/odbc.ini";
        $cmd          = "rpm -ql mysql-connector-odbc | grep libmyodbc..so";
        @rpmoutput    = xCAT::Utils->runcmd($cmd, 0);
    }
    elsif ($::debianflag) {
        $odbcinstfile = "/etc/odbcinst.ini";
        $odbcfile     = "/etc/odbc.ini";
        $cmd          = "dpkg -L libmyodbc | grep libmyodbc.so";
        @rpmoutput    = xCAT::Utils->runcmd($cmd, 0);
    }
    else
    {    #sles
        $odbcinstfile = "/etc/unixODBC/odbcinst.ini ";
        $odbcfile     = "/etc/unixODBC/odbc.ini ";
        $cmd          = "rpm -ql rpm -ql MyODBC-unixODBC | grep libmyodbc..so";
        @rpmoutput    = xCAT::Utils->runcmd($cmd, 0);
    }
    if ($::RUNCMD_RC != 0)
    {
        my $message = "Cannot configure the ODBC.";
        xCAT::MsgUtils->message("E", "$message");
        exit(1);
    }

    # setup the odbcinst.ini file
    my $sharedlib = $rpmoutput[0];
    $cmd = "fgrep -i  MySQL $odbcinstfile ";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)    # then driver entry not there
    {
        my $entry =
          "[MySQL]\nDescription = ODBC for MySQL\nDriver      = $sharedlib";
        $cmd = "echo \"$entry\" >> $odbcinstfile";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            $message = "Could not setup ODBC.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);
        }
    }
    else
    {    # entry already there
        $message = "$odbcinstfile already configured, will not change.";
        xCAT::MsgUtils->message("I", "$message");
    }

    # setup the DSN odbc.ini file
    $cmd = "fgrep -i MySQL $odbcfile";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)    # then xcat entry not there
    {
        my $entry =
"[xCATDB]\nDriver   = MySQL\nSERVER   = $server\nPORT     = 3306\nDATABASE = xcatdb";
        $cmd = "echo \"$entry\" >> $odbcfile";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            $message = "Could not setup ODBC DNS file.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);

        }
    }
    else
    {    # entry already there
        $message = "$odbcfile already configured, will not change.";
        xCAT::MsgUtils->message("I", "$message");
    }

    # setup $roothome/.odbc.ini so root will not have to specify password
    # when accessing through ODBC

    my $homedir      = xCAT::Utils->getHomeDir();
    my $rootodbcfile = $homedir;
    if ($::osname eq "AIX")
    {
        $rootodbcfile .= ".odbc.ini";
    }
    else
    {
        $rootodbcfile .= "/.odbc.ini";
    }

    # setup the DSN odbc.ini file
    $cmd = "fgrep -i  XCATDB $rootodbcfile";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)    # then xcat entry not there
    {
        my $entry =
"[xCATDB]\nSERVER =$server\nDATABASE = xcatdb\nUSER     = $adminid\nPASSWORD = $passwd";
        $cmd = "echo \"$entry\" >> $rootodbcfile";

        # secure passwd in verbose mode
        my $tmpv = $::VERBOSE;
        $::VERBOSE = 0;
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            $message = "Could not setup root ODBC file.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);

        }
        $::VERBOSE = $tmpv;
    }
    else
    {    # entry already there
        $message = "$rootodbcfile already configured, will not change. Make sure the userid and password are correct for MySQL";
        xCAT::MsgUtils->message("I", "$message");
    }

    # allow readonly by root
    chmod 0600, $rootodbcfile;

}

#-----------------------------------------------------------------------------

=head3   createcfgloc

                 Creates the cfgloc.mysql file which will be copied to cfgloc
                 to run xCAT on MySQL

=cut

#-----------------------------------------------------------------------------

sub createcfgloc

{
    my $cfglocmysql       = "/etc/xcat/cfgloc.mysql";
    my $cfglocmysqlbackup = "/etc/xcat/cfgloc.mysql.backup";
    my $cmd;
    my $message;
    if (-e ($cfglocmysql))
    {
        $cmd = "mv  $cfglocmysql $cfglocmysqlbackup";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            $message = "$cmd failed.";
            xCAT::MsgUtils->message("E", "$message");
            exit(1);

        }
    }
    my $mysqlentry =
      "mysql:dbname=xcatdb;host=$::MN|xcatadmin|$::adminpassword";
    $cmd = "echo \"$mysqlentry\" > $cfglocmysql";

    # secure passwd in verbose mode
    my $tmpv = $::VERBOSE;
    $::VERBOSE = 0;
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        $message = "command failed. Could not setup cfgloc.mysql";
        xCAT::MsgUtils->message("E", "$message");
        exit(1);

    }
    $::VERBOSE = $tmpv;

    # allow readonly by root
    chmod 0600, $cfglocmysql;

}


#-----------------------------------------------------------------------------

=head3   restorexcatdb

                Restores the database from ~/xcat-dbback and restarts the xcatd using
                MySQL

=cut

#-----------------------------------------------------------------------------

sub restorexcatdb
{

    # copy the mysql cfgloc file
    my $cmd;

    # if they had an old cfgloc on another database, save it
    if ((-e ("/etc/xcat/cfgloc")) && (!(-e ("/etc/xcat/cfgloc.olddb"))))
    {
        $cmd = "cp /etc/xcat/cfgloc /etc/xcat/cfgloc.olddb";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("E", " $cmd failed.");
        }
    }

    # put in place cfgloc for mysql
    $cmd = "cp /etc/xcat/cfgloc.mysql /etc/xcat/cfgloc";
    xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("E", " $cmd failed.");
        exit(1);
    }

    # allow readonly by root
    chmod 0600, "/etc/xcat/cfgloc";

    # set the env variable for Table.pm for the new database
    my $xcatcfg;
    my $cfgl;
    open($cfgl, "<", "/etc/xcat/cfgloc");
    $xcatcfg = <$cfgl>;
    close($cfgl);
    chomp($xcatcfg);

    # restore the database
    xCAT::MsgUtils->message(
        "I",
"Restoring the xCAT Database with $::backupdir to MySQL database.\nThis could take several minutes."
    );
    if (!(-d $::backupdir))
    {    # does not exist, error
        xCAT::MsgUtils->message("E",
            " $::backupdir is missing. Cannot retore the database.");
        exit(1);
    }

    # restore it
    my $cmd = "XCATBYPASS=y XCATCFG=\"$xcatcfg\"  restorexCATdb -p $::backupdir";

    # not display passwords in verbose mode
    my $tmpv = $::VERBOSE;
    $::VERBOSE = 0;
    xCAT::Utils->runcmd($cmd, 0);
    $::VERBOSE = $tmpv;
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("E", " $cmd failed.");
        exit(1);
    }

    #
    # restart the daemon
    #
    my $xcmd;
    if ($::osname eq 'AIX')
    {
        $xcmd = "$::XCATROOT/sbin/restartxcatd";
        system($xcmd);
    }
    else
    {
        #$xcmd = "service xcatd restart";
        #my $ret = xCAT::Utils->restartservice("xcatd");
        my $ret = "/usr/sbin/xcatd";
        return $ret;
    }

}
