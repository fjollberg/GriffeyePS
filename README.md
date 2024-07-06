# GriffeyePS

Powershell utility functions to interact with [Griffeye CS](https://www.magnetforensics.com/products/magnet-griffeye/),
a system used to analyse large amounts of digital media, e.g. in child exploitation investigations.

Includes Powershell wrappers for the REST API and CLI interfaces provided by Magnet, as well as a VICS json parser
which can handle most common aspects of large VICS reports fast and with low memory requirements.

These tools are used to make scripting tools and automation flows around Griffeye CS. Due to large amounts of
data, automation is an essential component to speed up handling and free human resources for analysis.

## General information

### Output

The modules make heavy use of Write-Information, Write-Verbose etc. In order to get more information
about actions you may want to use arguments like -Verbose, -InformationAction Continue or similar
control of output.

