-- CAMPUS TOUR, SECOND EDITION - issued by the Board from the overnight survey.
-- Run: basewalk tour       (or: basewalk tour data.tour_campus monitor_x)
-- Stops are landmarks, not coordinates: "near" is a legend char from the
-- compiled level, so this tour survives remodels. Updated for current
-- doctrine: our mods are canon, five Points stand in the Record, the ME
-- system is live, and the Battery is doctrinally a lighting installation.
-- To publish a new tour, the Board commits another file like this one.
return {
  level = "data.basewalk_campus",
  loop = true,
  stops = {
    { near = "P",
      say = "Welcome to the Paperclip Corporation campus, anchored by the Gold Standard in its open Socket: every coordinate we own derives from that block, and the hole stays uncovered by law. Everything you are about to see is ground truth, compiled from the overnight survey — textures lie, probes don't. As of the pack update, our own mods are canon; the Corporation is now official content in its own world." },
    { near = "N",
      say = "The NOC, and the Big Board. The Board is never present in person; it speaks through Directives and telemetry, and possibly through this very program, which is either recursion or a haunting — we decline to investigate. With the ME system live, the entire Corporation fits on one wall: a completed census, which is our god." },
    { near = "N", index = 3,
      say = "More of the Big Board. Anything worth knowing is worth rendering at six frames per second, and every 62nd craft order rings the milestone bell — the number is sacred, and the reasons are in the Record." },
    { near = "C",
      say = "Netherite chests, each one set in place by hand under the Rule of the Hand. The all-netherite policy is Case Law, purchased the night the reject bins overflowed; the Bite is read aloud over the PA before any fix ships." },
    { near = "M",
      say = "Personnel. New Employees boot here, receive their firmware, perform the Commencement pirouette, and join the Payroll before sentiment can develop. The graduation rate is one hundred percent; the alternative is the Fallen, and their names are retired." },
    { near = "T",
      say = "The gem cutting table. The Operator carries a luck stat over one hundred — ratified as canon by the pack update — and the gems respawn out of fear, mostly perfect; we keep the table for tradition." },
    { near = "V",
      say = "The trader: the villager inside works for emeralds, and the Emerald Famine and the storage controller incident are Case Law now, precedent paid for in lost time. Where the emeralds actually go remains under seal." },
    { near = "S",
      say = "Legacy barrels from the wooden era. The ME system is absorbing their contents item by item and they know it; what cannot be digitized gets swept under the Carpet, where everything does. Please do not make eye contact." },
    { near = "X",
      say = "The trash can, holiest intake on campus: everything the House discards feeds the Condenser. Five Points have been minted from it to date, four short of the Ninefold — garbage in, gigawatts out. The Corporation was founded on the discovery that trash, sufficiently compressed, becomes a god." },
    { near = "R",
      say = "The Operator's bed, retained for morale and rarely used. The Night Shift has always been kept by whoever is still awake; as of this quarter, the building keeps it too." },
    { near = "P", index = 2,
      say = "That concludes the tour. East of here stands the Battery — artillery acquired this quarter, every gun doctrinally a lamp — and when the last sail is seated, the final item the Corporation ever produces will be a full charge, followed presumably by a memo. Press P to let the camera wander, or take the controls yourself; the tour now restarts forever, because that is what screensavers do." },
  },
}