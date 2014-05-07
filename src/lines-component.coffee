React = require 'react'
{div, span} = require 'reactionary'
{debounce, isEqual, isEqualForProperties, multiplyString} = require 'underscore-plus'
{$$} = require 'space-pen'

DummyLineNode = $$(-> @div className: 'line', style: 'position: absolute; visibility: hidden;', => @span 'x')[0]
AcceptFilter = {acceptNode: -> NodeFilter.FILTER_ACCEPT}


module.exports =
LinesComponent = React.createClass
  displayName: 'LinesComponent'

  lineGroupSize: 10

  render: ->
    if @isMounted()
      {editor, renderedRowRange, lineHeight, showIndentGuide} = @props
      [startRow, endRow] = renderedRowRange
      maxEndRow = editor.getLineCount()

      lineGroups = []
      lineGroupStartRow = startRow - (startRow % @lineGroupSize)

      while lineGroupStartRow < endRow
        lineGroupEndRow = Math.min(lineGroupStartRow + @lineGroupSize, maxEndRow)
        lineGroups.push(LineGroupComponent({
          key: lineGroupStartRow, startRow: lineGroupStartRow, endRow: lineGroupEndRow,
          editor, showIndentGuide, lineHeight
        }))
        lineGroupStartRow = lineGroupEndRow

    div {className: 'lines'}, lineGroups

  componentWillMount: ->
    @measuredLines = new WeakSet

  componentDidMount: ->
    @measureLineHeightAndCharWidth()

  shouldComponentUpdate: (newProps) ->
    return true unless isEqualForProperties(newProps, @props,  'renderedRowRange', 'fontSize', 'fontFamily', 'lineHeight', 'showIndentGuide')

    {renderedRowRange, pendingChanges} = newProps
    for change in pendingChanges
      return true unless change.end <= renderedRowRange.start or renderedRowRange.end <= change.start

    false

  componentDidUpdate: (prevProps) ->
    @measureLineHeightAndCharWidth() unless isEqualForProperties(prevProps, @props, 'fontSize', 'fontFamily', 'lineHeight')
    # @clearScopedCharWidths() unless isEqualForProperties(prevProps, @props, 'fontSize', 'fontFamily')
    # @measureCharactersInNewLines() unless @props.scrollingVertically

  measureLineHeightAndCharWidth: ->
    node = @getDOMNode()
    node.appendChild(DummyLineNode)
    lineHeight = DummyLineNode.getBoundingClientRect().height
    charWidth = DummyLineNode.firstChild.getBoundingClientRect().width
    node.removeChild(DummyLineNode)

    {editor} = @props
    editor.setLineHeight(lineHeight)
    editor.setDefaultCharWidth(charWidth)

  measureCharactersInNewLines: ->
    [visibleStartRow, visibleEndRow] = @props.renderedRowRange
    node = @getDOMNode()

    for tokenizedLine, i in @props.editor.linesForScreenRows(visibleStartRow, visibleEndRow - 1)
      unless @measuredLines.has(tokenizedLine)
        lineNode = node.children[i]
        @measureCharactersInLine(tokenizedLine, lineNode)

  measureCharactersInLine: (tokenizedLine, lineNode) ->
    {editor} = @props
    rangeForMeasurement = null
    iterator = null
    charIndex = 0

    for {value, scopes}, tokenIndex in tokenizedLine.tokens
      charWidths = editor.getScopedCharWidths(scopes)

      for char in value
        unless charWidths[char]?
          unless textNode?
            rangeForMeasurement ?= document.createRange()
            iterator =  document.createNodeIterator(lineNode, NodeFilter.SHOW_TEXT, AcceptFilter)
            textNode = iterator.nextNode()
            textNodeIndex = 0
            nextTextNodeIndex = textNode.textContent.length

          while nextTextNodeIndex <= charIndex
            textNode = iterator.nextNode()
            textNodeIndex = nextTextNodeIndex
            nextTextNodeIndex = textNodeIndex + textNode.textContent.length

          i = charIndex - textNodeIndex
          rangeForMeasurement.setStart(textNode, i)
          rangeForMeasurement.setEnd(textNode, i + 1)
          charWidth = rangeForMeasurement.getBoundingClientRect().width
          editor.setScopedCharWidth(scopes, char, charWidth)

        charIndex++

    @measuredLines.add(tokenizedLine)

  clearScopedCharWidths: ->
    @measuredLines.clear()
    @props.editor.clearScopedCharWidths()

LineGroupComponent = React.createClass
  displayName: 'LineGroupComponent'

  render: ->
    {editor, startRow, endRow, lineHeight, showIndentGuide} = @props

    style = {WebkitTransform: "translate3d(0, #{startRow * lineHeight}px, 0)"}

    div {className: 'line-group', style},
      for tokenizedLine, i in editor.linesForScreenRows(startRow, endRow - 1)
        LineComponent({key: tokenizedLine.id, tokenizedLine, showIndentGuide, screenRow: startRow + i})

  shouldComponentUpdate: (newProps) ->
    false
    # not isEqualForProperties(newProps, @props, 'showIndentGuide', 'lineHeight')

LineComponent = React.createClass
  displayName: 'LineComponent'

  render: ->
    {screenRow, lineHeight} = @props
    div className: 'line', 'data-screen-row': screenRow, dangerouslySetInnerHTML: {__html: @buildInnerHTML()}

  buildInnerHTML: ->
    if @props.tokenizedLine.text.length is 0
      @buildEmptyLineHTML()
    else
      @buildScopeTreeHTML(@props.tokenizedLine.getScopeTree())

  buildEmptyLineHTML: ->
    {showIndentGuide, tokenizedLine} = @props
    {indentLevel, tabLength} = tokenizedLine

    if showIndentGuide and indentLevel > 0
      indentSpan = "<span class='indent-guide'>#{multiplyString(' ', tabLength)}</span>"
      multiplyString(indentSpan, indentLevel + 1)
    else
      "&nbsp;"

  buildScopeTreeHTML: (scopeTree) ->
    if scopeTree.children?
      html = "<span class='#{scopeTree.scope.replace(/\./g, ' ')}'>"
      html += @buildScopeTreeHTML(child) for child in scopeTree.children
      html += "</span>"
      html
    else
      "<span>#{scopeTree.getValueAsHtml({hasIndentGuide: @props.showIndentGuide})}</span>"

  shouldComponentUpdate: (newProps) ->
    not isEqualForProperties(newProps, @props, 'showIndentGuide', 'lineHeight')
