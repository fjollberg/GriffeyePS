# Modules

A breif description of the purpose of the included modules.
s
### GriffeyePS

An empty module which just references all the other modules for convenience.

### GriffeyeAPI

A wrapper module for interaction with the Griffeye REST API from Powershell.
Uses GriffeyeJsonParser.

### GriffeyeJsonParser

A module based on NewtonSoft.Json to parse large VICS metadata files effectively
and using reasonable amounts of memory. Makes it possible to get the media information
of large VICS reports as a stream starting immediately rather than after 30 minutes
of processing and 100GB of RAM. Due to NewtonSoft.Json this is a Windows-only module.

### GrifffeyeCLI

A thin wrapper module to run the Griffeye Connect CLI (connect-cli.exe) with
reasonable handling of output and errors in a Powershell context. Only meaningful
with connect-cli.exe, i.e. on Windows as far as I'm aware.

### GriffeyeNCMEC

A module which can take NCMEC reports (or similar output from some workflow
systems consuming NCMEC reports), create a VICS Json and upload the information
into a Griffeye case using GriffeyeAPI.
