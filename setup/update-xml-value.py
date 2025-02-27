#!/usr/bin/env python3

import sys
import xml.etree.ElementTree as ElementTree

if len(sys.argv) < 5:
    print('Usage: update-xml-value.py <in-out-file> <xpath> <attr-name> <new-value> [-d]')
    exit(1)

inFile = sys.argv[1]
xpath = sys.argv[2]
attr = sys.argv[3]
value = sys.argv[4]
is_del = len(sys.argv) > 5 and sys.argv[5].lower() == '-d'


class CommentedTreeBuilder(ElementTree.TreeBuilder):
    def comment(self, data):
        self.start(ElementTree.Comment, {})
        self.data(data)
        self.end(ElementTree.Comment)


def update_value(node0):
    if is_del:
        if len(attr) == 0:
            raise Exception('Delete operation is not supported without attribute name')
        else:
            del node0.attrib[attr]
    else:
        if len(attr) == 0:
            node0.text = value
        else:
            node0.attrib[attr] = value

parser = ElementTree.XMLParser(target=CommentedTreeBuilder())
tree = ElementTree.parse(inFile, parser)
root = tree.getroot()

if len(xpath) == 0:
    update_value(root)
else:
    for node in root.findall(xpath):
        update_value(node)

tree.write(inFile, encoding='utf-8', xml_declaration=True)
