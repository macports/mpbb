These files are intended to be used with portindex(1)'s -p option. They
contain pairs of variable names and values, where the values are what
could be set for each variable on the platform described in the file
name. This allows the generated index to more accurately resemble what
would be generated if portindex were actually run on that platform.

Example usage:

portindex -p file:./index_vars/macosx_24_arm
