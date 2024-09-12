#!/usr/bin/env python

import sys
import xml.etree.ElementTree as ElementTree

if len(sys.argv) < 3:
    print('Usage: insert-xml-node.py <in-out-file> <node-in-file> <xpath of node where append child> [xpath of nodes what append]')
    exit(1)

inFile = sys.argv[1]
childInFile = sys.argv[2]
xpath = sys.argv[3]
xpath_nodes_to_append = sys.argv[4] if len(sys.argv) > 4 else ''


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

parser2 = ElementTree.XMLParser(target=CommentedTreeBuilder())
treeChild = ElementTree.parse(childInFile, parser2)
root = tree.getroot()
childRoot = treeChild.getroot()

nodes = [root] if len(xpath) == 0 else root.findall(xpath)
nodes_to_append = [childRoot] if len(xpath_nodes_to_append) == 0 else childRoot.findall(xpath_nodes_to_append)

for node in nodes:
    for node_to_append in nodes_to_append:
        node.append(node_to_append)

indent(root)

tree.write(inFile, encoding='utf-8', xml_declaration=True)
