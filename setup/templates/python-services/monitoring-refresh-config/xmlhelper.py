from xml.dom import minidom
from xml.etree import ElementTree


def prettify_xml(elem):
    rough_string = ElementTree.tostring(elem, 'utf-8')
    minidom_tree = minidom.parseString(rough_string)
    return minidom_tree.toprettyxml(indent="	")


# TODO: input-output examples
def dict_to_xml_element(input_dict, output_tag_name):
    xml_elem = ElementTree.Element(output_tag_name)
    for key, value in input_dict.items():
        attr = ElementTree.SubElement(xml_elem, key)
        attr.text = value
    return xml_elem


# TODO: input-output examples
def rows_to_xml_elements(rows, root_tag_name, child_tag_name):
    root_elem = ElementTree.Element(root_tag_name)
    for row in rows:
        root_elem.append(dict_to_xml_element(row, child_tag_name))
    return root_elem
