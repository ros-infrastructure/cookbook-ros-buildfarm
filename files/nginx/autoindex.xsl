<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:param name="title"/>
	<xsl:template match="/">
		<html>
			<head>
				<title><xsl:value-of select="$title"/></title>
				<style>
					table { font-size: 1.5em; font-family: monospace; }
					td { min-width: 16em; }
				</style>
			</head>
			<body>
				<h2><xsl:value-of select="$title"/></h2>
				<hr/>
				<table>
					<xsl:if test="not($title = 'Index of /')"><a href=".. (Parent Directory)">..</a></xsl:if>
					<xsl:for-each select="/list/directory">
						<tr>
							<td><a>
									<xsl:attribute name="href"><xsl:value-of select="."/>/</xsl:attribute>
									<xsl:value-of select="."/>/</a></td>
							<td><xsl:value-of select="@mtime"/></td>
							<td>
								<xsl:if test="boolean(@size)"><xsl:value-of select="@size"/></xsl:if>
								<xsl:if test="not(boolean(@size))">—</xsl:if>
							</td>
						</tr>
					</xsl:for-each>
					<xsl:for-each select="/list/file">
						<tr>
							<td><a>
									<xsl:attribute name="href"><xsl:value-of select="."/></xsl:attribute>
									<xsl:value-of select="."/></a></td>
							<td><xsl:value-of select="@mtime"/></td>
							<td>
								<xsl:if test="boolean(@size)"><xsl:value-of select="@size"/></xsl:if>
								<xsl:if test="not(boolean(@size))">—</xsl:if>
							</td>
						</tr>
					</xsl:for-each>
				</table>
				<hr/>
			</body>
		</html>
	</xsl:template>
</xsl:stylesheet>


