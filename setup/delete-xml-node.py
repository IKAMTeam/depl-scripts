#!/usr/bin/env python

import sys
import xml.etree.ElementTree as ElementTree

if len(sys.argv) < 3:
    print('Usage: delete-xml-node.py <in-out-file> <xpath of node(s) which should be deleted>')
    exit(1)

inFile = sys.argv[1]
childInFile = sys.argv[2]
xpath = sys.argv[3]


class CommentedTreeBuilder(ElementTree.TreeBuilder):
    def comment(self, data):
        self.start(ElementTree.Comment, {})
        self.data(data)
        self.end(ElementTree.Comment)


def indent(elem, level=0):
    i = "\n" + level * "    "
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + "    "
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level + 1)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = i


parser = ElementTree.XMLParser(target=CommentedTreeBuilder())
tree = ElementTree.parse(inFile, parser)
root = tree.getroot()

for node in root.findall(xpath):
    root.remove(node)

indent(root)

tree.write(inFile, encoding='utf-8', xml_declaration=True)
