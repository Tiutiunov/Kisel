#pragma once

#include <QRegularExpression>
#include <QString>

namespace kisel {

// A processor's or a graphics card's name as its maker spells it, cut to what a person
// calls it: the maker, the trademark signs and the padding go, the line and the model stay.
//
//   "AMD Ryzen 5 5600H with Radeon Graphics"       -> "Ryzen 5 5600H"
//   "12th Gen Intel(R) Core(TM) i7-12700H"          -> "Core i7-12700H"
//   "Intel(R) Core(TM) i5-9400F CPU @ 2.90GHz"      -> "Core i5-9400F"
//   "AMD Ryzen 7 5800X 8-Core Processor"            -> "Ryzen 7 5800X"
//   "NVIDIA GeForce RTX 3050 Laptop GPU"            -> "RTX 3050 Laptop"
//   "AMD Radeon RX 6700 XT"                         -> "Radeon RX 6700 XT"
//   "Intel(R) UHD Graphics 630"                     -> "UHD Graphics 630"
//
// A name none of this fits is left as it is, tidied.
inline QString shortPartName(const QString &full)
{
    QString s = full;
    static const QRegularExpression marks(QStringLiteral("\\((R|TM|C)\\)"), QRegularExpression::CaseInsensitiveOption);
    s.replace(marks, QStringLiteral(" "));
    static const QRegularExpression tail(QStringLiteral("\\s+(with\\s+Radeon.*|@.*|w/.*)$"), QRegularExpression::CaseInsensitiveOption);
    s.remove(tail);
    static const QRegularExpression padding(
        QStringLiteral("\\b(\\d+(st|nd|rd|th)\\s+Gen|\\d+-Core|Processor|CPU|GPU|NVIDIA|GeForce|AMD|Intel|Genuine|Corporation)\\b"),
        QRegularExpression::CaseInsensitiveOption);
    s.remove(padding);
    s = s.simplified();
    return s.isEmpty() ? full.simplified() : s;
}

} // namespace kisel
