import Foundation
import SwiftUI

// The chat's own labels. Kept in code rather than .strings files so the
// package needs no localisation setup in the host app, and so Hollo.language
// can switch them without the app changing its own locale.

struct HolloStrings: Equatable {
    var support: String
    var replyTime: String
    var done: String
    var close: String
    var emptyTitle: String
    var emptyText: String
    var placeholder: String
    var send: String
    var sending: String
    var waiting: String
    var failed: String
    var offline: String
    var copy: String
    var ai: String
    var reviewText: String
    var leaveReview: String
    var open: String
    var seeOffer: String
    var pushReplies: String
    var pushRepliesOffers: String
    var noThanks: String
    var continueLabel: String
    var notifyLine: String
    var addPhotos: String
    var removePhoto: String
    var photo: String
    var photoNumber: String
    var closePhoto: String
    var photoFailed: String
    var confirm: String
    var cancel: String
    var confirmed: String
    var cancelled: String
    var expired: String
    var noLongerAvailable: String
    var confirmFailed: String
    var layoutDirection: LayoutDirection = .leftToRight

    /** "Photo", or "Photo 2 of 3" when there are several, for VoiceOver. */
    func photoLabel(_ number: Int, of total: Int) -> String {
        total > 1 ? String(format: photoNumber, number, total) : photo
    }

    /** For a code like "fr", "pt-BR" or nil (the device's language). */
    static func forLanguage(_ code: String?) -> HolloStrings {
        let full = (code ?? Locale.preferredLanguages.first ?? "en").lowercased()
        let base = String(full.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "en")
        var strings = table[base] ?? english
        // Laid out right to left even before these languages are translated.
        if ["ar", "he", "iw", "ur", "fa"].contains(base) {
            strings.layoutDirection = .rightToLeft
        }
        return strings
    }

    static let english = HolloStrings(
        support: "Support",
        replyTime: "We usually reply in a few minutes",
        done: "Done",
        close: "Close support chat",
        emptyTitle: "How can we help?",
        emptyText: "Send us a message and we'll get back to you right here.",
        placeholder: "Message",
        send: "Send message",
        sending: "Sending…",
        waiting: "Sends when you're back online",
        failed: "Not sent. Tap to retry.",
        offline: "Couldn't reach support. Retrying…",
        copy: "Copy",
        ai: "AI",
        reviewText: "Enjoying the app? A quick review helps us a lot.",
        leaveReview: "Leave a review",
        open: "Open",
        seeOffer: "See offer",
        pushReplies: "Turn on notifications so you know when we reply?",
        pushRepliesOffers: "Turn on notifications to hear about replies and offers?",
        noThanks: "No thanks",
        continueLabel: "Continue",
        notifyLine: "We'll send you a notification when we reply.",
        addPhotos: "Add photos",
        removePhoto: "Remove photo",
        photo: "Photo",
        photoNumber: "Photo %1$d of %2$d",
        closePhoto: "Close photo",
        photoFailed: "Couldn't add that photo.",
        confirm: "Confirm",
        cancel: "Cancel",
        confirmed: "Confirmed",
        cancelled: "Cancelled",
        expired: "Expired",
        noLongerAvailable: "No longer available",
        confirmFailed: "Couldn't send that. Try again."
    )

    private static let table: [String: HolloStrings] = [
        "en": english,
        "es": HolloStrings(
            support: "Soporte",
            replyTime: "Solemos responder en pocos minutos",
            done: "Listo",
            close: "Cerrar el chat de soporte",
            emptyTitle: "¿En qué podemos ayudarte?",
            emptyText: "Escríbenos y te responderemos aquí mismo.",
            placeholder: "Mensaje",
            send: "Enviar mensaje",
            sending: "Enviando…",
            waiting: "Se enviará cuando vuelva la conexión",
            failed: "No enviado. Toca para reintentar.",
            offline: "No hay conexión con soporte. Reintentando…",
            copy: "Copiar",
            ai: "IA",
            reviewText: "¿Te gusta la app? Una reseña rápida nos ayuda mucho.",
            leaveReview: "Escribir una reseña",
            open: "Abrir",
            seeOffer: "Ver oferta",
            pushReplies: "¿Activar notificaciones para saber cuándo respondemos?",
            pushRepliesOffers: "¿Activar notificaciones para enterarte de respuestas y ofertas?",
            noThanks: "No, gracias",
            continueLabel: "Continuar",
            notifyLine: "Te enviaremos una notificación cuando respondamos.",
            addPhotos: "Añadir fotos",
            removePhoto: "Quitar foto",
            photo: "Foto",
            photoNumber: "Foto %1$d de %2$d",
            closePhoto: "Cerrar foto",
            photoFailed: "No se pudo añadir la foto.",
            confirm: "Confirmar",
            cancel: "Cancelar",
            confirmed: "Confirmado",
            cancelled: "Cancelado",
            expired: "Caducado",
            noLongerAvailable: "Ya no está disponible",
            confirmFailed: "No se pudo enviar. Inténtalo de nuevo."
        ),
        "fr": HolloStrings(
            support: "Assistance",
            replyTime: "Nous répondons généralement en quelques minutes",
            done: "OK",
            close: "Fermer le chat d’assistance",
            emptyTitle: "Comment pouvons-nous vous aider\u{00A0}?",
            emptyText: "Envoyez-nous un message, nous vous répondrons ici.",
            placeholder: "Message",
            send: "Envoyer le message",
            sending: "Envoi…",
            waiting: "Sera envoyé dès le retour de la connexion",
            failed: "Non envoyé. Touchez pour réessayer.",
            offline: "Impossible de joindre l’assistance. Nouvelle tentative…",
            copy: "Copier",
            ai: "IA",
            reviewText: "Vous aimez l’app\u{00A0}? Un petit avis nous aide beaucoup.",
            leaveReview: "Laisser un avis",
            open: "Ouvrir",
            seeOffer: "Voir l’offre",
            pushReplies: "Activer les notifications pour savoir quand nous répondons\u{00A0}?",
            pushRepliesOffers: "Activer les notifications pour les réponses et les offres\u{00A0}?",
            noThanks: "Non merci",
            continueLabel: "Continuer",
            notifyLine: "Nous vous enverrons une notification dès notre réponse.",
            addPhotos: "Ajouter des photos",
            removePhoto: "Retirer la photo",
            photo: "Photo",
            photoNumber: "Photo %1$d sur %2$d",
            closePhoto: "Fermer la photo",
            photoFailed: "Impossible d’ajouter cette photo.",
            confirm: "Confirmer",
            cancel: "Annuler",
            confirmed: "Confirmé",
            cancelled: "Annulé",
            expired: "Expiré",
            noLongerAvailable: "Plus disponible",
            confirmFailed: "Échec de l’envoi. Réessayez."
        ),
        "de": HolloStrings(
            support: "Support",
            replyTime: "Wir antworten meist innerhalb weniger Minuten",
            done: "Fertig",
            close: "Support-Chat schließen",
            emptyTitle: "Wie können wir helfen?",
            emptyText: "Schreib uns eine Nachricht – wir antworten dir direkt hier.",
            placeholder: "Nachricht",
            send: "Nachricht senden",
            sending: "Wird gesendet…",
            waiting: "Wird gesendet, sobald die Verbindung zurück ist",
            failed: "Nicht gesendet. Zum Wiederholen tippen.",
            offline: "Support nicht erreichbar. Neuer Versuch…",
            copy: "Kopieren",
            ai: "KI",
            reviewText: "Gefällt dir die App? Eine kurze Bewertung hilft uns sehr.",
            leaveReview: "Bewertung schreiben",
            open: "Öffnen",
            seeOffer: "Angebot ansehen",
            pushReplies: "Mitteilungen aktivieren, damit du unsere Antwort mitbekommst?",
            pushRepliesOffers: "Mitteilungen für Antworten und Angebote aktivieren?",
            noThanks: "Nein danke",
            continueLabel: "Weiter",
            notifyLine: "Wir benachrichtigen dich, sobald wir antworten.",
            addPhotos: "Fotos hinzufügen",
            removePhoto: "Foto entfernen",
            photo: "Foto",
            photoNumber: "Foto %1$d von %2$d",
            closePhoto: "Foto schließen",
            photoFailed: "Das Foto konnte nicht hinzugefügt werden.",
            confirm: "Bestätigen",
            cancel: "Abbrechen",
            confirmed: "Bestätigt",
            cancelled: "Abgebrochen",
            expired: "Abgelaufen",
            noLongerAvailable: "Nicht mehr verfügbar",
            confirmFailed: "Konnte nicht gesendet werden. Bitte erneut versuchen."
        ),
        "pt": HolloStrings(
            support: "Suporte",
            replyTime: "Costumamos responder em poucos minutos",
            done: "OK",
            close: "Fechar o chat de suporte",
            emptyTitle: "Como podemos ajudar?",
            emptyText: "Envie uma mensagem e responderemos aqui mesmo.",
            placeholder: "Mensagem",
            send: "Enviar mensagem",
            sending: "Enviando…",
            waiting: "Será enviada quando a conexão voltar",
            failed: "Não enviada. Toque para tentar de novo.",
            offline: "Sem conexão com o suporte. Tentando de novo…",
            copy: "Copiar",
            ai: "IA",
            reviewText: "Está gostando do app? Uma avaliação rápida ajuda muito.",
            leaveReview: "Avaliar o app",
            open: "Abrir",
            seeOffer: "Ver oferta",
            pushReplies: "Ativar notificações para saber quando respondermos?",
            pushRepliesOffers: "Ativar notificações para respostas e ofertas?",
            noThanks: "Agora não",
            continueLabel: "Continuar",
            notifyLine: "Enviaremos uma notificação quando respondermos.",
            addPhotos: "Adicionar fotos",
            removePhoto: "Remover foto",
            photo: "Foto",
            photoNumber: "Foto %1$d de %2$d",
            closePhoto: "Fechar foto",
            photoFailed: "Não foi possível adicionar a foto.",
            confirm: "Confirmar",
            cancel: "Cancelar",
            confirmed: "Confirmado",
            cancelled: "Cancelado",
            expired: "Expirado",
            noLongerAvailable: "Não está mais disponível",
            confirmFailed: "Não foi possível enviar. Tente de novo."
        ),
        "it": HolloStrings(
            support: "Assistenza",
            replyTime: "Di solito rispondiamo in pochi minuti",
            done: "Fine",
            close: "Chiudi la chat di assistenza",
            emptyTitle: "Come possiamo aiutarti?",
            emptyText: "Scrivici un messaggio e ti risponderemo qui.",
            placeholder: "Messaggio",
            send: "Invia messaggio",
            sending: "Invio…",
            waiting: "Verrà inviato quando torna la connessione",
            failed: "Non inviato. Tocca per riprovare.",
            offline: "Impossibile contattare l’assistenza. Nuovo tentativo…",
            copy: "Copia",
            ai: "IA",
            reviewText: "Ti piace l’app? Una breve recensione ci aiuta molto.",
            leaveReview: "Scrivi una recensione",
            open: "Apri",
            seeOffer: "Vedi offerta",
            pushReplies: "Attivare le notifiche per sapere quando rispondiamo?",
            pushRepliesOffers: "Attivare le notifiche per risposte e offerte?",
            noThanks: "No, grazie",
            continueLabel: "Continua",
            notifyLine: "Ti invieremo una notifica quando rispondiamo.",
            addPhotos: "Aggiungi foto",
            removePhoto: "Rimuovi foto",
            photo: "Foto",
            photoNumber: "Foto %1$d di %2$d",
            closePhoto: "Chiudi foto",
            photoFailed: "Impossibile aggiungere la foto.",
            confirm: "Conferma",
            cancel: "Annulla",
            confirmed: "Confermato",
            cancelled: "Annullato",
            expired: "Scaduto",
            noLongerAvailable: "Non più disponibile",
            confirmFailed: "Invio non riuscito. Riprova."
        ),
    ]
}
