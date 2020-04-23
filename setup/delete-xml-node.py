#!/usr/bin/env python

import sys
import xml.etree.ElementTree as ElementTree

if len(sys.argv) < 4:
    print('Usage: delete-xml-node.py <in-out-file> <xpath of parent node(s)> <xpath of node(s) which should be deleted>')
    exit(1)

inFile = sys.argv[1]
xpath1 = sys.argv[2]
xpath2 = sys.argv[3]


class CommentedTreeBuilder(ElementTree.TreeBuilder):
    def comment(self, data):
        self.start(ElementTree.Comment, {})
        self.data(data)
        self.end(ElementTree.Comment)


parser = ElementTree.XMLParser(target=CommentedTreeBuilder())
tree = ElementTree.parse(inFile, parser)
root = tree.getroot()

for parentNode in root.findall(xpath1):
    for childNode in parentNode.findall(xpath2):
        parentNode.remove(childNode)

tree.write(inFile, encoding='utf-8', xml_declaration=True)
