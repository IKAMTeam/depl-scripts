from xml.dom import minidom
from xml.etree import ElementTree
from onevizion import Message


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


def compare_xml_elements(a, b):
    """ Compares 2 Elements to make sure they are Logically Equivalent
    by afaulconbridge
    https://stackoverflow.com/questions/7905380/testing-equivalence-of-xml-etree-elementtree"""

    if a.tag < b.tag:
        return -1
    elif a.tag > b.tag:
        return 1

    # compare attributes
    a_attributes = sorted(a.attrib.items())
    b_attributes = sorted(b.attrib.items())
    if a_attributes < b_attributes:
        return -1
    elif a_attributes > b_attributes:
        return 1

    # compare child nodes
    a_children_elements = list(a)
    a_children_elements.sort(key=functools.cmp_to_key(compare_xml_elements))
    b_children_elements = list(b)
    b_children_elements.sort(key=functools.cmp_to_key(compare_xml_elements))
    if len(a_children_elements) < len(b_children_elements):
        return -1
    elif len(a_children_elements) > len(b_children_elements):
        return 1

    a_text = a.text
    if a_text is None:
        a_text = ''

    b_text = b.text
    if b_text is None:
        b_text = ''

    if a_text.strip() != b_text.strip():
        Message(f"Tag='{a.tag}' A='{a.text}' B='{b.text}'", 1)
        return -1

    # with the ordered list of children, recursively check on each
    cmp_val = 0
    for a_child_element, b_child_element in zip(a_children_elements, b_children_elements):
        cmp_val = compare_xml_elements(a_child_element, b_child_element)

    if cmp_val < 0:
        return -1
    elif cmp_val > 0:
        return 1

    # if it made it this far, must be equal
    return 0
