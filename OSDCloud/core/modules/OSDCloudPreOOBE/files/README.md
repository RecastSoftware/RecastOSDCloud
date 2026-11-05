# OSDCloud PreOOBE application manifest examples

Each JSON file is a sample manifest. Copy the chosen file into an application
package folder beside its installer, rename it to `OSDCloudPreOOBE.json`, and
replace the example executable name and arguments with the installer's actual
values.

`Conditions` filters applications by device manufacturer, model, and/or native
OS architecture. Different condition fields are combined with AND; multiple
patterns within one field are combined with OR. The manifest schema does not
support dependencies between application packages.
