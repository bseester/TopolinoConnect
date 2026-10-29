package local.topolinoconnect.gateway

/** Reassembles ASCII serial lines split across arbitrary USB reads. */
internal class SerialLineAccumulator(private val maxLineLength: Int = 4096) {
    private val current = StringBuilder()
    private var discardingOversizedLine = false

    fun append(bytes: ByteArray): List<String> {
        val completeLines = ArrayList<String>()
        bytes.forEach { byte ->
            val character = (byte.toInt() and 0xff).toChar()
            if (character == '\n') {
                if (!discardingOversizedLine) current.toString().trim().takeIf(String::isNotEmpty)?.let(completeLines::add)
                current.setLength(0)
                discardingOversizedLine = false
            } else if (!discardingOversizedLine) {
                if (current.length < maxLineLength) current.append(character)
                else {
                    current.setLength(0)
                    discardingOversizedLine = true
                }
            }
        }
        return completeLines
    }
}
