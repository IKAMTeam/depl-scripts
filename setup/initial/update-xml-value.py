#!/usr/bin/env python

import sys
import xml.etree.ElementTree as ElementTree

if len(sys.argv) < 5:
    print('Usage: update-xml-value.py <in-out-file> [xpath] <attr-name> <new-value>')
    exit(1)

inFile = sys.argv[1]
xpath = sys.argv[2]
attr = sys.argv[3]
value = sys.argv[4]


class CommentedTreeBuilder(ElementTree.TreeBuilder):
    def comment(self, data):
        self.start(ElementTree.Comment, {})
        self.data(data)
        self.end(ElementTree.Comment)


parser = ElementTree.XMLParser(target=CommentedTreeBuilder())
tree = ElementTree.parse(inFile, parser)
root = tree.getroot()

if len(xpath) == 0:
    root.attrib[attr] = value
else:
    for node in root.findall(xpath):
        node.attrib[attr] = value

tree.write(inFile, encoding='utf-8', xml_declaration=True)
