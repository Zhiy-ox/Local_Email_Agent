import SwiftUI

struct EmailCardView: View {
    let email: EmailItem
    

    var body: some View {
        let label = email.importance >= 3 ? "CRITICAL" : email.importance == 2 ? "HIGH" : email.importance == 1 ? "MEDIUM" : "LOW"
        let importanceColor: Color = email.importance >= 3 ? .red : email.importance == 2 ? .orange : email.importance == 1 ? .blue : .gray
        
        VStack(alignment: .leading, spacing: 16) {
            // Header: Date
            Text(email.date)
                .font(.custom("GillSans-Light", size: 13))
                .foregroundStyle(Color.white.opacity(0.7).shadow(.inner(color: .black.opacity(0.9), radius: 1.5, x: 0, y: 1)))
            
            // Content: Summary
            Text(email.summary)
                .font(.custom("GillSans-Light", size: 19))
                .foregroundStyle(Color.white.opacity(0.9).shadow(.inner(color: .black.opacity(0.9), radius: 2, x: 0, y: 1.5)))
                .lineLimit(4)
                .truncationMode(.tail)
            
            Spacer(minLength: 0)
            
            // Footer: Action Area
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(importanceColor.opacity(0.2))
                    .foregroundColor(importanceColor)
                    .cornerRadius(10)
                
                Spacer()
                
                if email.eventPreview != nil {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                }
            }
        }
        .padding(24)
        .frame(width: 330, height: 210)
        // Physical Frosted Glass Fix (prevents recursive magnifying bug from glassEffect)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08)) // Internal frosted brightness
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0.1), .white.opacity(0.0), .black.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        // Physical Drop Shadows
        // 1. Soft, wide shadow for depth and occlusion
        .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 10)
        // 2. Tight, darker contact shadow to ground it physically
        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 3)

    }
}

struct EmailCardView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            EmailCardView(email: EmailItem(idx: 1, subject: "Review the new MacOS App Designs", sender: "Tim Cook", summary: "Please take a look at the newly proposed glassmorphic interfaces for the upcoming update.", importance: 3, date: "Today", eventPreview: nil))
        }
        .frame(width: 400, height: 400)
    }
}
