# Teleport
Tiny CoreLoction spoofing lib.

Let's say that for some reason you want your movements to be shifted by some fixed offset(lat/lon). 
Now you can do that by just: 

1. Placing `Teleport.swift` into your project.
2. Updating the offset in the constants to the required one. 
3. Calling `Teleport.initialize()` from your `AppDelegate`.
