#import "DDXMLPrivate.h"
#import "NSString+DDXML.h"

#import <libxml/xpath.h>
#import <libxml/xpathInternals.h>


@implementation DDXMLNode

static void MyErrorHandler(void * userData, xmlErrorPtr error);

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;
		
		// Redirect error output to our own function (don't clog up the console)
		initGenericErrorDefaultFunc(NULL);
		xmlSetStructuredErrorFunc(NULL, MyErrorHandler);
		
		// Tell libxml not to keep ignorable whitespace (such as node indentation, formatting, etc).
		// NSXML ignores such whitespace.
		// This also has the added benefit of taking up less RAM when parsing formatted XML documents.
		xmlKeepBlanksDefault(0);
	}
}

+ (id)elementWithName:(NSString *)name
{
	return [[[DDXMLElement alloc] initWithName:name] autorelease];
}

+ (id)elementWithName:(NSString *)name stringValue:(NSString *)string
{
	return [[[DDXMLElement alloc] initWithName:name stringValue:string] autorelease];
}

+ (id)elementWithName:(NSString *)name children:(NSArray *)children attributes:(NSArray *)attributes
{
	DDXMLElement *result = [[[DDXMLElement alloc] initWithName:name] autorelease];
	[result setChildren:children];
	[result setAttributes:attributes];
	
	return result;
}

+ (id)elementWithName:(NSString *)name URI:(NSString *)URI
{
	return [[[DDXMLElement alloc] initWithName:name URI:URI] autorelease];
}

+ (id)attributeWithName:(NSString *)name stringValue:(NSString *)stringValue
{
	xmlAttrPtr attr = xmlNewProp(NULL, [name xmlChar], [stringValue xmlChar]);
	
	if (attr == NULL) return nil;
	
	return [[[DDXMLAttributeNode alloc] initWithAttrPrimitive:attr freeOnDealloc:YES] autorelease];
}

+ (id)attributeWithName:(NSString *)name URI:(NSString *)URI stringValue:(NSString *)stringValue
{
	xmlAttrPtr attr = xmlNewProp(NULL, [name xmlChar], [stringValue xmlChar]);
	
	if (attr == NULL) return nil;
	
	DDXMLAttributeNode *result = [[DDXMLAttributeNode alloc] initWithAttrPrimitive:attr freeOnDealloc:YES];
	[result setURI:URI];
	
	return [result autorelease];
}

+ (id)namespaceWithName:(NSString *)name stringValue:(NSString *)stringValue
{
	// If the user passes a nil or empty string name, they are trying to create a default namespace
	const xmlChar *xmlName = [name length] > 0 ? [name xmlChar] : NULL;
	
	xmlNsPtr ns = xmlNewNs(NULL, [stringValue xmlChar], xmlName);
	
	if (ns == NULL) return nil;
	
	return [[[DDXMLNamespaceNode alloc] initWithNsPrimitive:ns nsParent:NULL freeOnDealloc:YES] autorelease];
}

+ (id)processingInstructionWithName:(NSString *)name stringValue:(NSString *)stringValue
{
	xmlNodePtr procInst = xmlNewPI([name xmlChar], [stringValue xmlChar]);
	
	if (procInst == NULL) return nil;
	
	return [[[DDXMLNode alloc] initWithPrimitive:(xmlKindPtr)procInst freeOnDealloc:YES] autorelease];
}

+ (id)commentWithStringValue:(NSString *)stringValue
{
	xmlNodePtr comment = xmlNewComment([stringValue xmlChar]);
	
	if (comment == NULL) return nil;
	
	return [[[DDXMLNode alloc] initWithPrimitive:(xmlKindPtr)comment freeOnDealloc:YES] autorelease];
}

+ (id)textWithStringValue:(NSString *)stringValue
{
	xmlNodePtr text = xmlNewText([stringValue xmlChar]);
	
	if (text == NULL) return nil;
	
	return [[[DDXMLNode alloc] initWithPrimitive:(xmlKindPtr)text freeOnDealloc:YES] autorelease];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init, Dealloc
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (id)nodeWithUnknownPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	if (kindPtr->type == XML_DOCUMENT_NODE)
	{
		return [DDXMLDocument nodeWithDocPrimitive:(xmlDocPtr)kindPtr freeOnDealloc:flag];
	}
	else if (kindPtr->type == XML_ELEMENT_NODE)
	{
		return [DDXMLElement nodeWithElementPrimitive:(xmlNodePtr)kindPtr freeOnDealloc:flag];
	}
	else if (kindPtr->type == XML_NAMESPACE_DECL)
	{
		// Todo: This may be a problem...
		
		return [DDXMLNamespaceNode nodeWithNsPrimitive:(xmlNsPtr)kindPtr nsParent:NULL freeOnDealloc:flag];
	}
	else if (kindPtr->type == XML_ATTRIBUTE_NODE)
	{
		return [DDXMLAttributeNode nodeWithAttrPrimitive:(xmlAttrPtr)kindPtr freeOnDealloc:flag];
	}
	else
	{
		return [DDXMLNode nodeWithPrimitive:kindPtr freeOnDealloc:flag];
	}
}

/**
 * Returns a DDXML wrapper object for the given primitive node.
 * The given node MUST be non-NULL and of the proper type.
**/
+ (id)nodeWithPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	return [[[DDXMLNode alloc] initWithPrimitive:kindPtr freeOnDealloc:flag] autorelease];
}

/**
 * Returns a DDXML wrapper object for the given primitive node.
 * The given node MUST be non-NULL and of the proper type.
**/
- (id)initWithPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	if ((self = [super init]))
	{
		genericPtr = kindPtr;
		freeOnDealloc = flag;
	}
	return self;
}

- (void)dealloc
{
	if (freeOnDealloc)
	{
		if (IsXmlNsPtr(genericPtr))
		{
			xmlFreeNs((xmlNsPtr)genericPtr);
		}
		else if (IsXmlAttrPtr(genericPtr))
		{
			xmlFreeProp((xmlAttrPtr)genericPtr);
		}
		else if (IsXmlDtdPtr(genericPtr))
		{
			xmlFreeDtd((xmlDtdPtr)genericPtr);
		}
		else if (IsXmlDocPtr(genericPtr))
		{
			xmlFreeDoc((xmlDocPtr)genericPtr);
		}
		else if (IsXmlNodePtr(genericPtr))
		{
			xmlFreeNode((xmlNodePtr)genericPtr);
		}
		else
		{
			NSAssert1(NO, @"Cannot free unknown node type: %i", ((xmlKindPtr)genericPtr)->type);
		}
	}
	[super dealloc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Copying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	if (IsXmlDocPtr(genericPtr))
	{
		xmlDocPtr copyDocPtr = xmlCopyDoc((xmlDocPtr)genericPtr, 1);
		
		if (copyDocPtr == NULL) return nil;
		
		return [[DDXMLDocument alloc] initWithDocPrimitive:copyDocPtr freeOnDealloc:YES];
	}
	
	if (IsXmlNodePtr(genericPtr))
	{
		xmlNodePtr copyNodePtr = xmlCopyNode((xmlNodePtr)genericPtr, 1);
		
		if (copyNodePtr == NULL) return nil;
		
		if ([self isKindOfClass:[DDXMLElement class]])
			return [[DDXMLElement alloc] initWithElementPrimitive:copyNodePtr freeOnDealloc:YES];
		else
			return [[DDXMLNode alloc] initWithPrimitive:(xmlKindPtr)copyNodePtr freeOnDealloc:YES];
	}
	
	if (IsXmlAttrPtr(genericPtr))
	{
		xmlAttrPtr copyAttrPtr = xmlCopyProp(NULL, (xmlAttrPtr)genericPtr);
		
		if (copyAttrPtr == NULL) return nil;
		
		return [[DDXMLAttributeNode alloc] initWithAttrPrimitive:copyAttrPtr freeOnDealloc:YES];
	}
	
	if (IsXmlNsPtr(genericPtr))
	{
		xmlNsPtr copyNsPtr = xmlCopyNamespace((xmlNsPtr)genericPtr);
		
		if (copyNsPtr == NULL) return nil;
		
		return [[DDXMLNamespaceNode alloc] initWithNsPrimitive:copyNsPtr nsParent:NULL freeOnDealloc:YES];
	}
	
	if (IsXmlDtdPtr(genericPtr))
	{
		xmlDtdPtr copyDtdPtr = xmlCopyDtd((xmlDtdPtr)genericPtr);
		
		if (copyDtdPtr == NULL) return nil;
		
		return [[DDXMLNode alloc] initWithPrimitive:(xmlKindPtr)copyDtdPtr freeOnDealloc:YES];
	}
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (DDXMLNodeKind)kind
{
	if (genericPtr != NULL)
		return genericPtr->type;
	else
		return DDXMLInvalidKind;
}

- (void)setName:(NSString *)name
{
	// Note: DDXMLNamespaceNode overrides this method
	
	// The xmlNodeSetName function works for both nodes and attributes
	xmlNodeSetName((xmlNodePtr)genericPtr, [name xmlChar]);
}

- (NSString *)name
{
	// Note: DDXMLNamespaceNode overrides this method
	
	const char *name = (const char *)((xmlStdPtr)genericPtr)->name;
	
	if (name == NULL)
		return nil;
	else
		return [NSString stringWithUTF8String:name];
}

- (void)setStringValue:(NSString *)string
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	if (IsXmlNodePtr(genericPtr))
	{
		xmlStdPtr node = (xmlStdPtr)genericPtr;
		
		// Setting the content of a node erases any existing child nodes.
		// Therefore, we need to remove them properly first.
		[[self class] removeAllChildrenFromNode:(xmlNodePtr)node];
		
		xmlChar *escapedString = xmlEncodeSpecialChars(node->doc, [string xmlChar]);
		xmlNodeSetContent((xmlNodePtr)node, escapedString);
		xmlFree(escapedString);
	}
}

/**
 * Returns the content of the receiver as a string value.
 * 
 * If the receiver is a node object of element kind, the content is that of any text-node children.
 * This method recursively visits elements nodes and concatenates their text nodes in document order with
 * no intervening spaces.
**/
- (NSString *)stringValue
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	if (IsXmlNodePtr(genericPtr))
	{
		xmlChar *content = xmlNodeGetContent((xmlNodePtr)genericPtr);
		
		NSString *result = [NSString stringWithUTF8String:(const char *)content];
		
		xmlFree(content);
		return result;
	}
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Tree Navigation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the index of the receiver identifying its position relative to its sibling nodes.
 * The first child node of a parent has an index of zero.
**/
- (NSUInteger)index
{
	// Note: DDXMLNamespaceNode overrides this method
	
	NSUInteger result = 0;
	
	xmlStdPtr node = ((xmlStdPtr)genericPtr)->prev;
	while (node != NULL)
	{
		result++;
		node = node->prev;
	}
	
	return result;
}

/**
 * Returns the nesting level of the receiver within the tree hierarchy.
 * The root element of a document has a nesting level of one.
**/
- (NSUInteger)level
{
	// Note: DDXMLNamespaceNode overrides this method
	
	NSUInteger result = 0;
	
	xmlNodePtr currentNode = ((xmlStdPtr)genericPtr)->parent;
	while (currentNode != NULL)
	{
		result++;
		currentNode = currentNode->parent;
	}
	
	return result;
}

/**
 * Returns the DDXMLDocument object containing the root element and representing the XML document as a whole.
 * If the receiver is a standalone node (that is, a node at the head of a detached branch of the tree), this
 * method returns nil.
**/
- (DDXMLDocument *)rootDocument
{
	// Note: DDXMLNamespaceNode overrides this method
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	
	if (node == NULL || node->doc == NULL)
		return nil;
	else
		return [DDXMLDocument nodeWithDocPrimitive:node->doc freeOnDealloc:NO];
}

/**
 * Returns the parent node of the receiver.
 * 
 * Document nodes and standalone nodes (that is, the root of a detached branch of a tree) have no parent, and
 * sending this message to them returns nil. A one-to-one relationship does not always exists between a parent and
 * its children; although a namespace or attribute node cannot be a child, it still has a parent element.
**/
- (DDXMLNode *)parent
{
	// Note: DDXMLNamespaceNode overrides this method
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	
	if (node->parent == NULL)
		return nil;
	else
		return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)node->parent freeOnDealloc:NO];
}

/**
 * Returns the number of child nodes the receiver has.
 * For performance reasons, use this method instead of getting the count from the array returned by children.
**/
- (NSUInteger)childCount
{
	// Note: DDXMLNamespaceNode overrides this method
	
	if (!IsXmlDocPtr(genericPtr) && !IsXmlNodePtr(genericPtr) && !IsXmlDtdPtr(genericPtr))
	{
		return 0;
	}
	
	NSUInteger result = 0;
	
	xmlNodePtr child = ((xmlStdPtr)genericPtr)->children;
	while (child != NULL)
	{
		result++;
		child = child->next;
	}
	
	return result;
}

/**
 * Returns an immutable array containing the child nodes of the receiver (as DDXMLNode objects).
**/
- (NSArray *)children
{
	// Note: DDXMLNamespaceNode overrides this method
	
	if (!IsXmlDocPtr(genericPtr) && !IsXmlNodePtr(genericPtr) && !IsXmlDtdPtr(genericPtr))
	{
		return nil;
	}
	
	NSMutableArray *result = [NSMutableArray array];
	
	xmlNodePtr child = ((xmlStdPtr)genericPtr)->children;
	while (child != NULL)
	{
		[result addObject:[DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)child freeOnDealloc:NO]];
		
		child = child->next;
	}
	
	return [[result copy] autorelease];
}

/**
 * Returns the child node of the receiver at the specified location.
 * Returns a DDXMLNode object or nil if the receiver has no children.
 * 
 * If the receive has children and index is out of bounds, an exception is raised.
 * 
 * The receiver should be a DDXMLNode object representing a document, element, or document type declaration.
 * The returned node object can represent an element, comment, text, or processing instruction.
**/
- (DDXMLNode *)childAtIndex:(NSUInteger)index
{
	// Note: DDXMLNamespaceNode overrides this method
	
	if (!IsXmlDocPtr(genericPtr) && !IsXmlNodePtr(genericPtr) && !IsXmlDtdPtr(genericPtr))
	{
		return nil;
	}
	
	NSUInteger i = 0;
	
	xmlNodePtr child = ((xmlStdPtr)genericPtr)->children;
	
	if (child == NULL)
	{
		// NSXML doesn't raise an exception if there are no children
		return nil;
	}
	
	while (child != NULL)
	{
		if (i == index)
		{
			return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)child freeOnDealloc:NO];
		}
		
		i++;
		child = child->next;
	}
	
	// NSXML version uses this same assertion
	DDXMLAssert(NO, @"index (%u) beyond bounds (%u)", (unsigned)index, (unsigned)i);
	
	return nil;
}

/**
 * Returns the previous DDXMLNode object that is a sibling node to the receiver.
 * 
 * This object will have an index value that is one less than the receiver�s.
 * If there are no more previous siblings (that is, other child nodes of the receiver�s parent) the method returns nil.
**/
- (DDXMLNode *)previousSibling
{
	// Note: DDXMLNamespaceNode overrides this method
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	
	if (node->prev == NULL)
		return nil;
	else
		return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)node->prev freeOnDealloc:NO];
}

/**
 * Returns the next DDXMLNode object that is a sibling node to the receiver.
 * 
 * This object will have an index value that is one more than the receiver�s.
 * If there are no more subsequent siblings (that is, other child nodes of the receiver�s parent) the
 * method returns nil.
**/
- (DDXMLNode *)nextSibling
{
	// Note: DDXMLNamespaceNode overrides this method
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	
	if (node->next == NULL)
		return nil;
	else
		return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)node->next freeOnDealloc:NO];
}

/**
 * Returns the previous DDXMLNode object in document order.
 * 
 * You use this method to �walk� backward through the tree structure representing an XML document or document section.
 * (Use nextNode to traverse the tree in the opposite direction.) Document order is the natural order that XML
 * constructs appear in markup text. If you send this message to the first node in the tree (that is, the root element),
 * nil is returned. DDXMLNode bypasses namespace and attribute nodes when it traverses a tree in document order.
**/
- (DDXMLNode *)previousNode
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	// If the node has a previous sibling,
	// then we need the last child of the last child of the last child etc
	
	// Note: Try to accomplish this task without creating dozens of intermediate wrapper objects
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	xmlStdPtr previousSibling = node->prev;
	
	if (previousSibling != NULL)
	{
		if (previousSibling->last != NULL)
		{
			xmlNodePtr lastChild = previousSibling->last;
			while (lastChild->last != NULL)
			{
				lastChild = lastChild->last;
			}
			
			return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)lastChild freeOnDealloc:NO];
		}
		else
		{
			// The previous sibling has no children, so the previous node is simply the previous sibling
			return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)previousSibling freeOnDealloc:NO];
		}
	}
	
	// If there are no previous siblings, then the previous node is simply the parent
	
	// Note: rootNode.parent == docNode
	
	if (node->parent == NULL || node->parent->type == XML_DOCUMENT_NODE)
		return nil;
	else
		return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)node->parent freeOnDealloc:NO];
}

/**
 * Returns the next DDXMLNode object in document order.
 * 
 * You use this method to �walk� forward through the tree structure representing an XML document or document section.
 * (Use previousNode to traverse the tree in the opposite direction.) Document order is the natural order that XML
 * constructs appear in markup text. If you send this message to the last node in the tree, nil is returned.
 * DDXMLNode bypasses namespace and attribute nodes when it traverses a tree in document order.
**/
- (DDXMLNode *)nextNode
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	// If the node has children, then next node is the first child
	DDXMLNode *firstChild = [self childAtIndex:0];
	if (firstChild)
		return firstChild;
	
	// If the node has a next sibling, then next node is the same as next sibling
	
	DDXMLNode *nextSibling = [self nextSibling];
	if (nextSibling)
		return nextSibling;
	
	// There are no children, and no more siblings, so we need to get the next sibling of the parent.
	// If that is nil, we need to get the next sibling of the grandparent, etc.
	
	// Note: Try to accomplish this task without creating dozens of intermediate wrapper objects
	
	xmlNodePtr parent = ((xmlStdPtr)genericPtr)->parent;
	while (parent != NULL)
	{
		xmlNodePtr parentNextSibling = parent->next;
		if (parentNextSibling != NULL)
			return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)parentNextSibling freeOnDealloc:NO];
		else
			parent = parent->parent;
	}
	
	return nil;
}

/**
 * Detaches the receiver from its parent node.
 *
 * This method is applicable to DDXMLNode objects representing elements, text, comments, processing instructions,
 * attributes, and namespaces. Once the node object is detached, you can add it as a child node of another parent.
**/
- (void)detach
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	
	if (node->parent != NULL)
	{
		if (IsXmlNodePtr(genericPtr))
		{
			[[self class] detachChild:(xmlNodePtr)node fromNode:node->parent];
			freeOnDealloc = YES;
		}
	}
}

- (xmlStdPtr)XPathPreProcess:(NSMutableString *)result
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	return (xmlStdPtr)genericPtr;
}

- (NSString *)XPath
{
	NSMutableString *result = [NSMutableString stringWithCapacity:25];
	
	// Examples:
	// /rootElement[1]/subElement[4]/thisNode[2]
	// topElement/thisNode[2]
	
	xmlStdPtr node = [self XPathPreProcess:result];
	
	// Note: rootNode.parent == docNode
		
	while ((node != NULL) && (node->type != XML_DOCUMENT_NODE))
	{
		if ((node->parent == NULL) && (node->doc == NULL))
		{
			// We're at the top of the heirarchy, and there is no xml document.
			// Thus we don't use a leading '/', and we don't need an index.
			
			[result insertString:[NSString stringWithFormat:@"%s", node->name] atIndex:0];
		}
		else
		{
			// Find out what index this node is.
			// If it's the first node with this name, the index is 1.
			// If there are previous siblings with the same name, the index is greater than 1.
			
			int index = 1;
			xmlStdPtr prevNode = node->prev;
			
			while (prevNode != NULL)
			{
				if (xmlStrEqual(node->name, prevNode->name))
				{
					index++;
				}
				prevNode = prevNode->prev;
			}
			
			[result insertString:[NSString stringWithFormat:@"/%s[%i]", node->name, index] atIndex:0];
		}
		
		node = (xmlStdPtr)node->parent;
	}
	
	return [[result copy] autorelease];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark QNames
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the local name of the receiver.
 * 
 * The local name is the part of a node name that follows a namespace-qualifying colon or the full name if
 * there is no colon. For example, �chapter� is the local name in the qualified name �acme:chapter�.
**/
- (NSString *)localName
{
	// Note: DDXMLNamespaceNode overrides this method
	
	return [[self class] localNameForName:[self name]];
}

/**
 * Returns the prefix of the receiver�s name.
 * 
 * The prefix is the part of a namespace-qualified name that precedes the colon.
 * For example, �acme� is the local name in the qualified name �acme:chapter�.
 * This method returns an empty string if the receiver�s name is not qualified by a namespace.
**/
- (NSString *)prefix
{
	// Note: DDXMLNamespaceNode overrides this method
	
	return [[self class] prefixForName:[self name]];
}

/**
 * Sets the URI identifying the source of this document.
 * Pass nil to remove the current URI.
**/
- (void)setURI:(NSString *)URI
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	if (IsXmlNodePtr(genericPtr))
	{
		xmlNodePtr node = (xmlNodePtr)genericPtr;
		if (node->ns != NULL)
		{
			[[self class] removeNamespace:node->ns fromNode:node];
		}
		
		if (URI)
		{
			// Create a new xmlNsPtr, add it to the nsDef list, and make ns point to it
			xmlNsPtr ns = xmlNewNs(NULL, [URI xmlChar], NULL);
			ns->next = node->nsDef;
			node->nsDef = ns;
			node->ns = ns;
		}
	}
}

/**
 * Returns the URI associated with the receiver.
 * 
 * A node�s URI is derived from its namespace or a document�s URI; for documents, the URI comes either from the
 * parsed XML or is explicitly set. You cannot change the URI for a particular node other for than a namespace
 * or document node.
**/
- (NSString *)URI
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	if (IsXmlNodePtr(genericPtr))
	{
		xmlNodePtr node = (xmlNodePtr)genericPtr;
		if (node->ns != NULL)
		{
			return [NSString stringWithUTF8String:((const char *)node->ns->href)];
		}
	}
	
	return nil;
}

/**
 * Returns the local name from the specified qualified name.
 * 
 * Examples:
 * "a:node" -> "node"
 * "a:a:node" -> "a:node"
 * "node" -> "node"
 * nil - > nil
**/
+ (NSString *)localNameForName:(NSString *)name
{
	if (name)
	{
		NSRange range = [name rangeOfString:@":"];
		
		if (range.length != 0)
			return [name substringFromIndex:(range.location + range.length)];
		else
			return name;
	}
	return nil;
}

/**
 * Extracts the prefix from the given name.
 * If name is nil, or has no prefix, an empty string is returned.
 * 
 * Examples:
 * "a:deusty.com" -> "a"
 * "a:a:deusty.com" -> "a"
 * "node" -> ""
 * nil -> ""
**/
+ (NSString *)prefixForName:(NSString *)name
{
	if (name)
	{
		NSRange range = [name rangeOfString:@":"];
		
		if (range.length != 0)
		{
			return [name substringToIndex:range.location];
		}
	}
	return @"";
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Output
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [self XMLStringWithOptions:0];
}

- (NSString *)XMLString
{
	// Todo: Test XMLString for namespace node
	return [self XMLStringWithOptions:0];
}

- (NSString *)XMLStringWithOptions:(NSUInteger)options
{
	// xmlSaveNoEmptyTags:
	// Global setting, asking the serializer to not output empty tags
	// as <empty/> but <empty></empty>. those two forms are undistinguishable
	// once parsed.
	// Disabled by default
	
	if (options & DDXMLNodeCompactEmptyElement)
		xmlSaveNoEmptyTags = 0;
	else
		xmlSaveNoEmptyTags = 1;
	
	int format = 0;
	if (options & DDXMLNodePrettyPrint)
	{
		format = 1;
		xmlIndentTreeOutput = 1;
	}
	
	xmlBufferPtr bufferPtr = xmlBufferCreate();
	if (IsXmlNsPtr(genericPtr))
		xmlNodeDump(bufferPtr, NULL, (xmlNodePtr)genericPtr, 0, format);
	else
		xmlNodeDump(bufferPtr, ((xmlStdPtr)genericPtr)->doc, (xmlNodePtr)genericPtr, 0, format);
	
	if ([self kind] == DDXMLTextKind)
	{
		NSString *result = [NSString stringWithUTF8String:(const char *)bufferPtr->content];
		
		xmlBufferFree(bufferPtr);
		
		return result;
	}
	else
	{
		NSMutableString *resTmp = [NSMutableString stringWithUTF8String:(const char *)bufferPtr->content];
		CFStringTrimWhitespace((CFMutableStringRef)resTmp);
		
		xmlBufferFree(bufferPtr);
		
		return [[resTmp copy] autorelease];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XPath/XQuery
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSArray *)nodesForXPath:(NSString *)xpath error:(NSError **)error
{
	xmlXPathContextPtr xpathCtx;
	xmlXPathObjectPtr xpathObj;
	
	BOOL isTempDoc = NO;
	xmlDocPtr doc;
	
	if (IsXmlDocPtr(genericPtr))
	{
		doc = (xmlDocPtr)genericPtr;
	}
	else if (IsXmlNodePtr(genericPtr))
	{
		doc = ((xmlNodePtr)genericPtr)->doc;
		
		if(doc == NULL)
		{
			isTempDoc = YES;
			
			doc = xmlNewDoc(NULL);
			xmlDocSetRootElement(doc, (xmlNodePtr)genericPtr);
		}
	}
	else
	{
		return nil;
	}
	
	xpathCtx = xmlXPathNewContext(doc);
	xpathCtx->node = (xmlNodePtr)genericPtr;
		
	xmlNodePtr rootNode = (doc)->children;
	if(rootNode != NULL)
	{
		xmlNsPtr ns = rootNode->nsDef;
		while(ns != NULL)
		{
			xmlXPathRegisterNs(xpathCtx, ns->prefix, ns->href);
			
			ns = ns->next;
		}
	}
	
	xpathObj = xmlXPathEvalExpression([xpath xmlChar], xpathCtx);
	
	NSArray *result;
	
	if(xpathObj == NULL)
	{
		if(error) *error = [[self class] lastError];
		result = nil;
	}
	else
	{
		if(error) *error = nil;
		
		int count = xmlXPathNodeSetGetLength(xpathObj->nodesetval);
		
		if(count == 0)
		{
			result = [NSArray array];
		}
		else
		{
			NSMutableArray *mResult = [NSMutableArray arrayWithCapacity:count];
			
			int i;
			for (i = 0; i < count; i++)
			{
				xmlNodePtr node = xpathObj->nodesetval->nodeTab[i];
				
				[mResult addObject:[DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)node freeOnDealloc:NO]];
			}
			
			result = mResult;
		}
	}
	
	if(xpathObj) xmlXPathFreeObject(xpathObj);
	if(xpathCtx) xmlXPathFreeContext(xpathCtx);
	
	if (isTempDoc)
	{
		xmlUnlinkNode((xmlNodePtr)genericPtr);
		xmlFreeDoc(doc);
		
		// xmlUnlinkNode doesn't remove the doc ptr
		[[self class] recursiveStripDocPointersFromNode:(xmlNodePtr)genericPtr];
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ---------- MEMORY MANAGEMENT ARCHITECTURE ----------
// 
// KissXML is designed to be read-access thread-safe.
// It is not write-access thread-safe as this would require significant overhead.
// 
// What exactly does read-access thread-safe mean?
// It means that multiple threads can safely read from the same xml structure,
// so long as none of them attempt to alter the xml structure (add/remove nodes, change attributes, etc).
// 
// This read-access thread-safety includes parsed xml structures as well as xml structures created by you.
// Let's walk through a few examples to get a deeper understanding.
// 
// 
// 
// Example #1 - Parallel processing of children
// 
// DDXMLElement *root = [[DDXMLElement alloc] initWithXMLString:str error:nil];
// NSArray *children = [root children];
// 
// dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
// dispatch_apply([children count], q, ^(size_t i) {
//     DDXMLElement *child = [children objectAtIndex:i];
//     <process child>
// });
// 
// 
// 
// Example #2 - Safe vs Unsafe sub-element processing
// 
// DDXMLElement *root = [[DDXMLElement alloc] initWithXMLString:str error:nil];
// DDXMLElement *child = [root elementForName:@"starbucks"];
// 
// dispatch_async(queue, ^{
//     <process child>
// });
// 
// [root release]; <-------------- NOT safe!
// 
// But why is it not safe?
// Does it have something to do with the child?
// Do I need to retain the child?
// Doesn't the child get retained automatically by dispatch_async?
// 
// Yes, the child does get retainied automatically by dispatch_async, but that's not the problem.
// XML represents a heirarchy of nodes. For example:
// 
// <root>
//   <starbucks>
//     <coffee/>
//   </starbucks>
// </root>
//     
// Each element within the heirarchy has references/pointers to its parent, children, siblings, etc.
// This is necessary to support the traversal strategies one requires to work with XML.
// This also means its not thread-safe to deallocate the root node of an element if
// you are still using/accessing a child node.
// So let's rewrite example 2 in a thread-safe manner this time.
// 
// DDXMLElement *root = [[DDXMLElement alloc] initWithXMLString:str error:nil];
// DDXMLElement *child = [root elementForName:@"starbucks"];
// 
// [child detach]; <-------------- Detached from root, and can safely be used even if we now dealloc root.
// 
// dispatch_async(queue, ^{
//     <process child>
// });
// 
// [root release]; <-------------- Thread-safe thanks to the detach above.
// 
// 
// 
// Example #3 - Building up an element
// 
// DDXMLElement *coffee    = [[DDXMLElement alloc] initWithName:@"coffee"];
// DDXMLElement *starbucks = [[DDXMLElement alloc] initWithName:@"starbucks"];
// DDXMLElement *root      = [[DDXMLElement alloc] initWithName:@"root"];
// 
// At this point we have 3 root nodes (root, starbucks, coffee)
// 
// [starbucks addChild:coffee];
// 
// At this point we have 2 root nodes (root, starbucks).
// The coffee node is now a child of starbucks, so it is no-longer a "root" node since
// it has a parent within the xml tree heirarchy.
// 
// [coffee addChild:starbucks];
// 
// At this point we have only 1 root node (root).
// Again, the others are no-longer "root" nodes since they have a parent within the xml tree heirarchy.
// 
// [coffee release]; coffee = nil;
// 
// If you have a reference to a child node, you can safely release that reference.
// Since coffee is embedded in the tree heirarchy, the coffee node doesn't disappear.
// 
// DDXMLElement *coffee2 = [starbucks elementForName:@"coffee"];
// 
// So the above will return a new reference to the coffee node.
// 
// [root release]; root = nil;
// 
// Now, we have just released the root node.
// This means that it is no longer safe to use starbucks or coffee2.
// 
// [starbucks release]; starbucks = nil;
// 
// Yes, this is safe. Just don't do anything else with starbucks besides release it.

/**
 * Returns whether or not the node has a parent.
 * Use this method instead of parent when you only need to ensure parent is nil.
 * This prevents the unnecessary creation of a parent node wrapper.
**/
- (BOOL)hasParent
{
	// Note: DDXMLNamespaceNode overrides this method
	
	xmlStdPtr node = (xmlStdPtr)genericPtr;
	
	return (node->parent != NULL);
}

+ (void)stripDocPointersFromAttr:(xmlAttrPtr)attr
{
	xmlNodePtr child = attr->children;
	while (child != NULL)
	{
		child->doc = NULL;
		child = child->next;
	}
	
	attr->doc = NULL;
}

+ (void)recursiveStripDocPointersFromNode:(xmlNodePtr)node
{
	xmlAttrPtr attr = node->properties;
	while (attr != NULL)
	{
		[self stripDocPointersFromAttr:attr];
		attr = attr->next;
	}
	
	xmlNodePtr child = node->children;
	while (child != NULL)
	{
		[self recursiveStripDocPointersFromNode:child];
		child = child->next;
	}
	
	node->doc = NULL;
}

/**
 * Detaches the given attribute from the given node.
 * The attribute's surrounding prev/next pointers are properly updated to remove the attribute from the attr list.
 * Then, if flag is YES, the attribute's parent, prev, next and doc pointers are destroyed.
**/
+ (void)detachAttribute:(xmlAttrPtr)attr fromNode:(xmlNodePtr)node andNullifyPointers:(BOOL)flag
{
	// Update the surrounding prev/next pointers
	if (attr->prev == NULL)
	{
		if (attr->next == NULL)
		{
			node->properties = NULL;
		}
		else
		{
			node->properties = attr->next;
			attr->next->prev = NULL;
		}
	}
	else
	{
		if (attr->next == NULL)
		{
			attr->prev->next = NULL;
		}
		else
		{
			attr->prev->next = attr->next;
			attr->next->prev = attr->prev;
		}
	}
	
	if (flag)
	{
		// Nullify pointers
		attr->parent = NULL;
		attr->prev   = NULL;
		attr->next   = NULL;
		if(attr->doc != NULL) [self stripDocPointersFromAttr:attr];
	}
}

/**
 * Detaches the given attribute from the given node.
 * The attribute's surrounding prev/next pointers are properly updated to remove the attribute from the attr list.
 * Then the attribute's parent, prev, next and doc pointers are destroyed.
**/
+ (void)detachAttribute:(xmlAttrPtr)attr fromNode:(xmlNodePtr)node
{
	[self detachAttribute:attr fromNode:node andNullifyPointers:YES];
}

/**
 * Removes and free's the given attribute from the given node.
 * The attribute's surrounding prev/next pointers are properly updated to remove the attribute from the attr list.
**/
+ (void)removeAttribute:(xmlAttrPtr)attr fromNode:(xmlNodePtr)node
{
	// We perform a bit of optimization here.
	// No need to bother nullifying pointers since we're about to free the node anyway.
	[self detachAttribute:attr fromNode:node andNullifyPointers:NO];
	
	xmlFreeProp(attr);
}

/**
 * Removes and frees all attributes from the given node.
 * Upon return, the given node's properties pointer is NULL.
**/
+ (void)removeAllAttributesFromNode:(xmlNodePtr)node
{
	xmlAttrPtr attr = node->properties;
	
	while (attr != NULL)
	{
		xmlAttrPtr nextAttr = attr->next;
		
		xmlFreeProp(attr);
		
		attr = nextAttr;
	}
	
	node->properties = NULL;
}

/**
 * Detaches the given namespace from the given node.
 * The namespace's surrounding next pointers are properly updated to remove the namespace from the node's nsDef list.
 * Then the namespace's parent and next pointers are destroyed.
**/
+ (void)detachNamespace:(xmlNsPtr)ns fromNode:(xmlNodePtr)node
{
	// Namespace nodes have no previous pointer, so we have to search for the node
	
	xmlNsPtr previousNs = NULL;
	xmlNsPtr currentNs = node->nsDef;
	
	while (currentNs != NULL)
	{
		if (currentNs == ns)
		{
			if (previousNs == NULL)
				node->nsDef = currentNs->next;
			else
				previousNs->next = currentNs->next;
			
			break;
		}
		
		previousNs = currentNs;
		currentNs = currentNs->next;
	}
	
	if (node->ns == ns)
	{
		node->ns = NULL;
	}
	
	// Nullify pointers
	//ns->_private = NULL; Todo
	ns->next = NULL;
}

/**
 * Removes the given namespace from the given node.
 * The namespace's surrounding next pointers are properly updated to remove the namespace from the nsDef list.
 * Then the namespace is freed if it's no longer being referenced.
 * Otherwise, it's nsParent and next pointers are destroyed.
**/
+ (void)removeNamespace:(xmlNsPtr)ns fromNode:(xmlNodePtr)node
{
	[self detachNamespace:ns fromNode:node];
	
	xmlFreeNs(ns);
}

/**
 * Removes all namespaces from the given node.
 * All namespaces are either freed, or their nsParent and next pointers are properly destroyed.
 * Upon return, the given node's nsDef pointer is NULL.
**/
+ (void)removeAllNamespacesFromNode:(xmlNodePtr)node
{
	xmlNsPtr ns = node->nsDef;
	
	while (ns != NULL)
	{
		xmlNsPtr nextNs = ns->next;
		
		xmlFreeNs(ns);
		
		ns = nextNs;
	}
	
	node->nsDef = NULL;
	node->ns = NULL;
}

/**
 * Detaches the given child from the given node.
 * The child's surrounding prev/next pointers are properly updated to remove the child from the node's children list.
 * Then, if flag is YES, the child's parent, prev, next and doc pointers are destroyed.
**/
+ (void)detachChild:(xmlNodePtr)child fromNode:(xmlNodePtr)node andNullifyPointers:(BOOL)flag
{
	// Update the surrounding prev/next pointers
	if (child->prev == NULL)
	{
		if (child->next == NULL)
		{
			node->children = NULL;
			node->last = NULL;
		}
		else
		{
			node->children = child->next;
			child->next->prev = NULL;
		}
	}
	else
	{
		if (child->next == NULL)
		{
			node->last = child->prev;
			child->prev->next = NULL;
		}
		else
		{
			child->prev->next = child->next;
			child->next->prev = child->prev;
		}
	}
	
	if (flag)
	{
		// Nullify pointers
		child->parent = NULL;
		child->prev   = NULL;
		child->next   = NULL;
		if(child->doc != NULL) [self recursiveStripDocPointersFromNode:child];
	}
}

/**
 * Detaches the given child from the given node.
 * The child's surrounding prev/next pointers are properly updated to remove the child from the node's children list.
 * Then the child's parent, prev, next and doc pointers are destroyed.
**/
+ (void)detachChild:(xmlNodePtr)child fromNode:(xmlNodePtr)node
{
	[self detachChild:child fromNode:node andNullifyPointers:YES];
}

/**
 * Removes the given child from the given node.
 * The child's surrounding prev/next pointers are properly updated to remove the child from the node's children list.
 * Then the child is recursively freed if it's no longer being referenced.
 * Otherwise, it's parent, prev, next and doc pointers are destroyed.
 * 
 * During the recursive free, subnodes still being referenced are properly handled.
**/
+ (void)removeChild:(xmlNodePtr)child fromNode:(xmlNodePtr)node
{
	// We perform a bit of optimization here.
	// No need to bother nullifying pointers since we're about to free the node anyway.
	[self detachChild:child fromNode:node andNullifyPointers:NO];
	
	xmlFreeNode(child);
}

/**
 * Removes all children from the given node.
 * All children are either recursively freed, or their parent, prev, next and doc pointers are properly destroyed.
 * Upon return, the given node's children pointer is NULL.
 * 
 * During the recursive free, subnodes still being referenced are properly handled.
**/
+ (void)removeAllChildrenFromNode:(xmlNodePtr)node
{
	xmlNodePtr child = node->children;
	
	while (child != NULL)
	{
		xmlNodePtr nextChild = child->next;
		
		xmlFreeNode(child);
		
		child = nextChild;
	}
	
	node->children = NULL;
	node->last = NULL;
}

/**
 * Returns the last error encountered by libxml.
 * Errors are caught in the MyErrorHandler method within DDXMLDocument.
**/
+ (NSError *)lastError
{
	NSValue *lastErrorValue = [[[NSThread currentThread] threadDictionary] objectForKey:DDLastErrorKey];
	if(lastErrorValue)
	{
		xmlError lastError;
		[lastErrorValue getValue:&lastError];
		
		int errCode = lastError.code;
		NSString *errMsg = [[NSString stringWithFormat:@"%s", lastError.message] stringByTrimming];
		
		NSDictionary *info = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
			
		return [NSError errorWithDomain:@"DDXMLErrorDomain" code:errCode userInfo:info];
	}
	else
	{
		return nil;
	}
}

static void MyErrorHandler(void * userData, xmlErrorPtr error)
{
	// This method is called by libxml when an error occurs.
	// We register for this error in the initialize method below.
	
	// Extract error message and store in the current thread's dictionary.
	// This ensure's thread safey, and easy access for all other DDXML classes.
	
	if (error == NULL)
	{
		[[[NSThread currentThread] threadDictionary] removeObjectForKey:DDLastErrorKey];
	}
	else
	{
		NSValue *errorValue = [NSValue valueWithBytes:error objCType:@encode(xmlError)];
		
		[[[NSThread currentThread] threadDictionary] setObject:errorValue forKey:DDLastErrorKey];
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation DDXMLNamespaceNode

/**
 * Returns a DDXML wrapper object for the given primitive node.
 * The given node MUST be non-NULL and of the proper type.
**/
+ (id)nodeWithNsPrimitive:(xmlNsPtr)ns nsParent:(xmlNodePtr)parent freeOnDealloc:(BOOL)flag
{
	return [[[DDXMLNamespaceNode alloc] initWithNsPrimitive:ns nsParent:parent freeOnDealloc:flag] autorelease];
}

/**
 * Returns a DDXML wrapper object for the given primitive node.
 * The given node MUST be non-NULL and of the proper type.
**/
- (id)initWithNsPrimitive:(xmlNsPtr)ns nsParent:(xmlNodePtr)parent  freeOnDealloc:(BOOL)flag
{
	if ((self = [super init]))
	{
		genericPtr = (xmlKindPtr)ns;
		nsParentPtr = parent;
		freeOnDealloc = flag;
	}
	return self;
}

+ (id)nodeWithPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes.
	NSAssert(NO, @"Use nodeWithNsPrimitive:nsParent:freeOnDealloc:");
	
	return nil;
}

- (id)initWithPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes.
	NSAssert(NO, @"Use initWithNsPrimitive:nsParent:freeOnDealloc:");
	
	[self release];
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setName:(NSString *)name
{
	xmlNsPtr ns = (xmlNsPtr)genericPtr;
	
	xmlFree((xmlChar *)ns->prefix);
	ns->prefix = xmlStrdup([name xmlChar]);
}

- (NSString *)name
{
	xmlNsPtr ns = (xmlNsPtr)genericPtr;
	if (ns->prefix != NULL)
		return [NSString stringWithUTF8String:((const char*)ns->prefix)];
	else
		return @"";
}

- (void)setStringValue:(NSString *)string
{
	xmlNsPtr ns = (xmlNsPtr)genericPtr;
	
	xmlFree((xmlChar *)ns->href);
	ns->href = xmlEncodeSpecialChars(NULL, [string xmlChar]);
}

- (NSString *)stringValue
{
	return [NSString stringWithUTF8String:((const char *)((xmlNsPtr)genericPtr)->href)];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Tree Navigation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)index
{
	xmlNsPtr ns = (xmlNsPtr)genericPtr;
	
	// The xmlNsPtr has no prev pointer, so we have to search from the parent
	
	if (nsParentPtr == NULL)
	{
		return 0;
	}
	
	NSUInteger result = 0;
	
	xmlNsPtr currentNs = nsParentPtr->nsDef;
	while (currentNs != NULL)
	{
		if (currentNs == ns)
		{
			return result;
		}
		result++;
		currentNs = currentNs->next;
	}
	
	return 0; // Yes 0, not result, because ns wasn't found in list
}

- (NSUInteger)level
{
	NSUInteger result = 0;
	
	xmlNodePtr currentNode = nsParentPtr;
	while (currentNode != NULL)
	{
		result++;
		currentNode = currentNode->parent;
	}
	
	return result;
}

- (DDXMLDocument *)rootDocument
{
	xmlStdPtr node = (xmlStdPtr)nsParentPtr;
	
	if (node == NULL || node->doc == NULL)
		return nil;
	else
		return [DDXMLDocument nodeWithDocPrimitive:node->doc freeOnDealloc:NO];
}

- (DDXMLNode *)parent
{
	if (nsParentPtr == NULL)
		return nil;
	else
		return [DDXMLNode nodeWithUnknownPrimitive:(xmlKindPtr)nsParentPtr freeOnDealloc:NO];
}

- (NSUInteger)childCount
{
	return 0;
}

- (NSArray *)children
{
	return nil;
}

- (DDXMLNode *)childAtIndex:(NSUInteger)index
{
	return nil;
}

- (DDXMLNode *)previousSibling
{
	return nil;
}

- (DDXMLNode *)nextSibling
{
	return nil;
}

- (DDXMLNode *)previousNode
{
	return nil;
}

- (DDXMLNode *)nextNode
{
	return nil;
}

- (void)detach
{
	if (nsParentPtr != NULL)
	{
		[DDXMLNode detachNamespace:(xmlNsPtr)genericPtr fromNode:nsParentPtr];
		
		freeOnDealloc = YES;
		nsParentPtr = NULL;
	}
}

- (xmlStdPtr)XPathPreProcess:(NSMutableString *)result
{
	xmlStdPtr parent = (xmlStdPtr)nsParentPtr;
		
	if (parent == NULL)
		[result appendFormat:@"namespace::%@", [self name]];
	else
		[result appendFormat:@"/namespace::%@", [self name]];
	
	return parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark QNames
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)localName
{
	// Strangely enough, the localName of a namespace is the prefix, and the prefix is an empty string
	xmlNsPtr ns = (xmlNsPtr)genericPtr;
	if (ns->prefix != NULL)
		return [NSString stringWithUTF8String:((const char *)ns->prefix)];
	else
		return @"";
}

- (NSString *)prefix
{
	// Strangely enough, the localName of a namespace is the prefix, and the prefix is an empty string
	return @"";
}

- (void)setURI:(NSString *)URI
{
	// Do nothing
}

- (NSString *)URI
{
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)hasParent
{
	return (nsParentPtr != NULL);
}

- (xmlNodePtr)nsParentPtr
{
	return nsParentPtr;
}

- (void)setNsParentPtr:(xmlNodePtr)parentPtr
{
	nsParentPtr = parentPtr;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation DDXMLAttributeNode

+ (id)nodeWithAttrPrimitive:(xmlAttrPtr)attr freeOnDealloc:(BOOL)flag
{
	return [[[DDXMLAttributeNode alloc] initWithAttrPrimitive:attr freeOnDealloc:flag] autorelease];
}

- (id)initWithAttrPrimitive:(xmlAttrPtr)attr freeOnDealloc:(BOOL)flag
{
	self = [super initWithPrimitive:(xmlKindPtr)attr freeOnDealloc:flag];
	return self;
}

+ (id)nodeWithPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes.
	NSAssert(NO, @"Use nodeWithAttrPrimitive:nsParent:freeOnDealloc:");
	
	return nil;
}

- (id)initWithPrimitive:(xmlKindPtr)kindPtr freeOnDealloc:(BOOL)flag
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes.
	NSAssert(NO, @"Use initWithAttrPrimitive:nsParent:freeOnDealloc:");
	
	[self release];
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setStringValue:(NSString *)string
{
	xmlAttrPtr attr = (xmlAttrPtr)genericPtr;
	
	if (attr->children != NULL)
	{
		xmlChar *escapedString = xmlEncodeSpecialChars(attr->doc, [string xmlChar]);
		xmlNodeSetContent((xmlNodePtr)attr, escapedString);
		xmlFree(escapedString);
	}
	else
	{
		xmlNodePtr text = xmlNewText([string xmlChar]);
		attr->children = text;
	}
}

- (NSString *)stringValue
{
	xmlAttrPtr attr = (xmlAttrPtr)genericPtr;
	
	if (attr->children != NULL)
	{
		return [NSString stringWithUTF8String:(const char *)attr->children->content];
	}
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Tree Navigation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (DDXMLNode *)previousNode
{
	return nil;
}

- (DDXMLNode *)nextNode
{
	return nil;
}

- (void)detach
{
	xmlAttrPtr attr = (xmlAttrPtr)genericPtr;
	
	if (attr->parent != NULL)
	{
		[[self class] detachAttribute:attr fromNode:attr->parent];
		freeOnDealloc = YES;
	}
}

- (xmlStdPtr)XPathPreProcess:(NSMutableString *)result
{
	// Note: DDXMLNamespaceNode overrides this method
	// Note: DDXMLAttributeNode overrides this method
	
	xmlAttrPtr attr = (xmlAttrPtr)genericPtr;
	xmlStdPtr parent = (xmlStdPtr)attr->parent;
	
	if (parent == NULL)
		[result appendFormat:@"@%@", [self name]];
	else
		[result appendFormat:@"/@%@", [self name]];
	
	return parent;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark QNames
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setURI:(NSString *)URI
{
	xmlAttrPtr attr = (xmlAttrPtr)genericPtr;
	if (attr->ns != NULL)
	{
		// An attribute can only have a single namespace attached to it.
		// In addition, this namespace can only be accessed via the URI method.
		// There is no way, within the API, to get a DDXMLNode wrapper for the attribute's namespace.
		xmlFreeNs(attr->ns);
		attr->ns = NULL;
	}
	
	if (URI)
	{
		// Create a new xmlNsPtr, and make ns point to it
		xmlNsPtr ns = xmlNewNs(NULL, [URI xmlChar], NULL);
		attr->ns = ns;
	}
}

- (NSString *)URI
{
	xmlAttrPtr attr = (xmlAttrPtr)genericPtr;
	if (attr->ns != NULL)
	{
		return [NSString stringWithUTF8String:((const char *)attr->ns->href)];
	}
	
	return nil;
}

@end
