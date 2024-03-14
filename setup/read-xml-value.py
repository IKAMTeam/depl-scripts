#!/usr/bin/env python3

import sys
import xml.etree.ElementTree as ElementTree

if len(sys.argv) < 4:
    print('Usage: read-xml-value.py <in-file> <xpath> [attr-name]')
    exit(1)

inFile = sys.argv[1]
xpath = sys.argv[2]
attr = sys.argv[3]

parser = ElementTree.XMLParser()
tree = ElementTree.parse(inFile, parser)
root = tree.getroot()


def print_value(node0):
    if len(attr) == 0:
        print(node0.text)
    else:
        print(node0.attrib[attr])


if len(xpath) == 0:
    print_value(root)
else:
    for node in root.findall(xpath):
        print_value(node)
