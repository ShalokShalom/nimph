import std/hashes
import std/os
from std/sequtils import toSeq
import std/uri except Url

import gittyup

import nimph/spec
import nimph/paths
import nimph/requirements
import nimph/versions

##[

these are just collection concepts that assert a little more convenience.

a Group is a collection that holds items that may be indexed by some
stable index. deletion should preserve order whenever possible. singleton
iteration yields the original item. pairwise iteration also yields unique
indices that can be used for deletion.

a FlaggedGroup additionally has a flags field/proc that yields set[Flag];
this is used to alter group operations to, for example, silently omit
errors and warnings (Quiet) or prevent destructive modification (DryRun).

]##

type
  ## the most basic of identity assumptions
  Suitable = concept
    proc hash(s: self): Hash
    proc `==`(a, b: self): bool

  ## a collection of suitable items
  Collectable[T: Suitable] = concept
    proc contains(c: self; n: T): bool
    proc len(c: self): int
    iterator items(c: self): T            # ...that you can iterate
    iterator pairs(c: self): (each I, T)  # pairs iteration yields the index
    proc del(c: self; index: I)           # the index can be used for deletion

  Groupable[T] = concept
    proc add(g: self; n: T)
    proc del(g: self; n: T)

  Group[T] = concept g, var w       ## add the concept of a unique index
    g is Groupable[T]
    incl(w, T)                      # do nothing if T's index exists
    excl(w, T)                      # do nothing if T's index does not exist
    for index, item in pairs(g):    # pairs iteration yields the index
      item is T
      item is Suitable
      add(w, index, T)              # it will raise if the index exists
      `[]`(w, index) is T           # get via index
      `[]=`(w, index, T)            # set via index

#[
  IdentityGroup*[T] = concept g, var w ##
    ## an IdentityGroup lets you test for membership via Identity,
    ## PackageName, or Uri
    g is Group[T]
    w is Group[T]
    contains(g, Identity) is bool
    contains(g, PackageName) is bool
    contains(g, Uri) is bool
    `[]`(g, PackageName) is T       # indexing by identity types
    `[]`(g, Uri) is T               # indexing by identity types
    `[]`(g, Identity) is T          # indexing by identity types

  ImportGroup*[T] = concept g, var w ##
    ## an ImportGroup lets you test for membership via ImportName
    g is Group[T]
    w is Group[T]
    importName(T) is ImportName
    contains(g, ImportName) is bool
    excl(w, ImportName)             # delete any T that yields ImportName
    `[]`(g, ImportName) is T        # index by ImportName

  GitGroup*[T] = concept g, var w ##
    ## a GitGroup is designed to hold Git objects like tags, references,
    ## commits, and so on
    g is Group[T]
    w is Group[T]
    oid(T) is GitOid
    contains(g, GitOid) is bool
    excl(w, GitOid)                 # delete any T that yields GitOid
    `[]`(g, GitOid) is T            # index by GitOid
    free(T)                         # ensure we can free the group

  ReleaseGroup*[T] = concept g, var w ##
    ## a ReleaseGroup lets you test for membership via Release,
    ## (likely Version, Tag, and such as well)
    g is Group[T]
    w is Group[T]
    contains(g, Release) is bool
    for item in g[Release]:         # indexing iteration by Release
      item is T
]#

proc incl*[T](group: Groupable[T]; value: T) =
  if value notin group:
    group.add value

proc excl*[T](group: Groupable[T]; value: T) =
  if value in group:
    group.del value

proc hash*(group: Collectable): Hash =
  var h: Hash = 0
  for item in items(group):
    h = h !& hash(item)
  result = !$h

iterator backwards*[T](group: Collectable): T =
  ## yield values in reverse order
  let items = toSeq items(group)
  for index in countDown(items.high, items.low):
    yield items[index]

proc contains*(group: Group; name: ImportName): bool =
  for item in items(group):
    result = item.importName == name
    if result:
      break

proc excl*(group: Group; name: ImportName) =
  while name in group:
    for item in items(group):
      if importName(item) == name:
        group.del item
        break

proc `[]`*[T](group: Group[T]; name: ImportName): T =
  block found:
    for item in items(group):
      if item.importName == name:
        result = item
        break found
    raise newException(KeyError, "not found")

proc free*(group: Group) =
  ## free GitGroup members
  while len(group) > 0:
    for item in items(group):
      group.del item
      break

proc contains*(group: Group; identity: Identity): bool =
  for item in items(group):
    result = item == identity
    if result:
      break

proc contains*(group: Group; name: PackageName): bool =
  result = newIdentity(name) in group

proc contains*(group: Group; url: Uri): bool =
  result = newIdentity(url) in group

proc add*[T](group: Group[T]; value: T) =
  if value in group:
    raise newException(KeyError, "duplicates not supported")
  group.incl value

proc `[]`*[T](group: Group[T]; identity: Identity): T =
  block found:
    for item in items(group):
      if item == identity:
        result = item
        break found
    raise newException(KeyError, "not found")

proc `[]`*[T](group: Group[T]; url: Uri): T =
  result = group[newIdentity(url)]

proc `[]`*[T](group: Group[T]; name: PackageName): T =
  result = group[newIdentity(name)]

proc del*[T](group: var Collectable[T]; value: T) =
  for index, item in pairs(group):
    if item == value:
      group.del index
      break

when isMainModule:
  import balls

  suite "concepts test":
    ## we start with a simple "collection".
    var g: seq[string]
    ## add some values.
    g.add "Goats"
    g.add "pigs"
    ## make an immutable copy.
    let h = g
    ## a string is a suitable type for tests.
    assert string is Suitable
    ## g is a Collectable of strings.
    assert g is Collectable[string]
    ## sure, fine, as expected.
    assert g is Collectable
    ## del() was written against Collectable
    g.del "pigs"
    ## ok, great.  and this works, for now!
    assert g is Groupable[string]
    ## this does not -- but why not?
    assert g is Groupable
    ## h is immutable, so isn't Groupable[string], right?
    assert h isnot Groupable[string]
    ## so does that mean we can add to h?
    h.add "horses"
    ## but wait, i thought h was Collectable
    assert h is Collectable
    ## so we can iterate and delete, right?
    for index, item in pairs(h):
      h.del index
      break
    ## oh, but we can use our del(var w, T)?
    h.del "pigs"
    ## right, so, uh, how is h a Groupable[string]?
    assert h is Groupable[string]
