
package MagickWand;

use Fcntl;
use Image::Magick;
use IO::Handle;

our @EXPORT_OK = qw(data_to_image image_to_data);
use base qw(Exporter);
our $tmpfile = "/tmp/wand${$}tmp";

sub data_to_image {
    my $data = shift;
    my $image = Image::Magick->new();

    open WAND, "+>$tmpfile" or die $!;
    binmode WAND;
    print WAND $data;
    close WAND;

    if (my $x = $image->Read(filename => $tmpfile )) {
	die $x;
    };

    unlink( $tmpfile );

    return $image;
}

sub image_to_data {
    my $image = shift;
    my $filename = shift || "img.png";

    if ($x = $image->Write(filename=>$tmpfile.$filename)) {
	die $x;
    };
    close WAND;

    sysopen( WAND, $tmpfile.$filename, O_RDONLY ) or die $!;
    my $data;
    my $length = (stat WAND)[7];
    sysread( WAND, $data, $length, 0 );
    close ( WAND );
    unlink( $tmpfile );

    return $data;
}

1;
