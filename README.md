# Cairo Documentation Solutions 
Author : [Mohit Gayatri](https://github.com/mgayatri77). 

This repository contains solutions to the exercises in the [Cairo Programming Language Documentation](https://starknet.io/docs/index.html). 

## Prerequisites
- Python version 3.6 or greater
- Cairo setup (https://starknet.io/docs/quickstart.html)

## Running the examples
Use the following commands to compile and run any of the examples:
```
cairo-compile program_name.cairo --output program_name_compiled.json
cairo-run --program=program_name_compiled.json --print_output --layout=small (**optional** program_input=program_name_input.json)
```