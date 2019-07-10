# Organelle_pd_extra
External objects compiled for Pd on the Organelle.  

# How to use
Inside the pd-extended folder are many libraries of objects and associated help patches.

Objects may be copied into your patch folder as they are needed.  Alternatively the whole set may be copied onto the root folder of USB drive and the individual libraries imported using the [declare] object.

So the USB drive would look like this:

/Patches
/pd-extended 

Then to use, for example, the counter object from the cyclone library,  your patch would do this:

[declare -path ../../pd-extended/cyclone]

For deploying / distributing / sharing patches it is better to copy the needed objects into your patch folder so it is self-contained,  this way the patch will work even if someone doesn't have all the objects copied to their USB drive.
