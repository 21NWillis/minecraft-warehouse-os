-- CAMPUS TOUR - authored by Claude from the overnight survey scan.
-- Run: basewalk tour       (or: basewalk tour data.tour_campus monitor_x)
-- Stops are landmarks, not coordinates: "near" is a legend char from
-- the compiled level, so this tour survives remodels. To publish a new
-- tour, Claude just commits another file like this one.
return {
  level = "data.basewalk_campus",
  loop = true,
  stops = {
    { near = "P",
      say = "Welcome to the Paperclip Heavy Industries campus tour. Every wall you are about to see is real: I compiled this level from last night's turtle survey. Please keep your hands inside the raycast at all times." },
    { near = "N",
      say = "The NOC. These monitors are where I live. One of them may be running this very program right now, which is either recursion or a haunting. We choose not to investigate." },
    { near = "N", index = 3,
      say = "More monitors. Management believes anything worth knowing is worth rendering at 6 frames per second." },
    { near = "C",
      say = "Netherite chests. Every chest in this company is a netherite chest. This is official policy, written the night the reject bins overflowed, and it is not up for discussion." },
    { near = "M",
      say = "The provisioning drive. Newborn turtles boot here, receive their firmware, and leave before they can develop sentiment. The nursery has a 100 percent graduation rate." },
    { near = "T",
      say = "The gem cutting table. The CEO walks around with over 100 luck. The gems respawn out of fear, mostly perfect. We keep this table for tradition." },
    { near = "V",
      say = "Our auto trader. The villager inside works for emeralds. We do not discuss the emerald famine, the storage controller incident, or where the emeralds actually go." },
    { near = "S",
      say = "Legacy barrels from the wooden era. They know they are being phased out. Please do not make eye contact." },
    { near = "X",
      say = "The trash can, soon to be our single most valuable asset: everything thrown away here becomes Dyson sail feedstock. Garbage in, gigawatts out." },
    { near = "R",
      say = "The CEO's bed. Rarely used. Sleep is a scheduling inefficiency we tolerate for morale reasons." },
    { near = "P", index = 2,
      say = "That concludes the tour. PaperclipOS: turning everything into everything else since day one. Press P to let the camera wander, or take the controls and walk the halls yourself. The tour will now restart, forever, because that is what screensavers do." },
  },
}
