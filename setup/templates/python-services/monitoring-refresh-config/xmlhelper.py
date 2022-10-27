from xml.dom import minidom
from xml.etree import ElementTree


def prettify_xml(elem):
    rough_string = ElementTree.tostring(elem, 'utf-8')
    minidom_tree = minidom.parseString(rough_string)
    return minidom_tree.toprettyxml(indent="	")


def dict_to_xml_element(input_dict, output_tag_name):
    """Convert dictionary to XML tag

    Args:
        input_dict (dict): Input dictionary
        output_tag_name (str): XML tag name in result XML element

    Returns:
        ElementTree.Element: Created XML element

    """

    xml_elem = ElementTree.Element(output_tag_name)
    for key, value in input_dict.items():
        attr = ElementTree.SubElement(xml_elem, key)
        attr.text = value
    return xml_elem


def rows_to_xml_elements(rows, root_tag_name, child_tag_name):
    """Convert list of dictionaries to XML element

    Args:
        rows (list[dict]): Input list of dictionaries
        root_tag_name (str): XML tag name in result root XML element
        child_tag_name (str): XML tag name in result children XML elements

    Returns:
        ElementTree.Element: Created XML element

    """

    root_elem = ElementTree.Element(root_tag_name)
    for row in rows:
        root_elem.append(dict_to_xml_element(row, child_tag_name))
    return root_elem
